/**
 * Workaround for a Qt 5 problem on Sailfish OS: after the phone switches
 * network (Wi-Fi <-> mobile data), QNetworkAccessManager can consider the
 * network permanently "not accessible". Every request then fails at once
 * with status 0 until the app is restarted.
 *
 * keepNetworkAccessible() forces the manager back to "accessible" each time
 * Qt changes it. NetworkFixFactory gives the QML engine (XMLHttpRequest,
 * images) managers with this fix.
 *
 * License: MIT
 */
#ifndef NETWORKFIX_H
#define NETWORKFIX_H

#include <QNetworkAccessManager>
#include <QNetworkConfigurationManager>
#include <QQmlNetworkAccessManagerFactory>
#include <QCoreApplication>
#include <QPointer>
#include <QTimer>
#include <QList>
#include <QMutex>
#include <QMutexLocker>

/*
 * After a network switch, Qt keeps reusing the connections it had opened on
 * the old network. They are dead, so requests wait on them for a long time
 * before failing. dropOldConnections() makes every manager forget them; it
 * runs shortly after each change of the phone's network.
 */
inline QMutex &networkFixMutex()
{
    static QMutex mutex;
    return mutex;
}

inline QList<QPointer<QNetworkAccessManager> > &networkFixManagers()
{
    static QList<QPointer<QNetworkAccessManager> > managers;
    return managers;
}

inline void dropOldConnections()
{
    QMutexLocker lock(&networkFixMutex());
    QList<QPointer<QNetworkAccessManager> > &managers = networkFixManagers();
    for (int i = managers.size() - 1; i >= 0; --i) {
        QNetworkAccessManager *manager = managers.at(i).data();
        if (!manager) {
            managers.removeAt(i);
            continue;
        }
        // run in the manager's own thread (QML may load images in another one)
        QTimer::singleShot(0, manager, [manager]() { manager->clearAccessCache(); });
    }
}

// To be called once from the main thread, after QGuiApplication exists.
inline void watchNetworkChanges()
{
    static bool started = false;
    if (started)
        return;
    started = true;

    QObject *app = QCoreApplication::instance();
    QNetworkConfigurationManager *configs = new QNetworkConfigurationManager(app);
    // several signals arrive for one switch: act once, 1 s after the last one
    QTimer *debounce = new QTimer(app);
    debounce->setSingleShot(true);
    debounce->setInterval(1000);
    QObject::connect(debounce, &QTimer::timeout, dropOldConnections);
    auto later = [debounce]() { debounce->start(); };
    QObject::connect(configs, &QNetworkConfigurationManager::onlineStateChanged, debounce, later);
    QObject::connect(configs, &QNetworkConfigurationManager::configurationAdded, debounce, later);
    QObject::connect(configs, &QNetworkConfigurationManager::configurationRemoved, debounce, later);
    QObject::connect(configs, &QNetworkConfigurationManager::configurationChanged, debounce,
                     [debounce](const QNetworkConfiguration &c) {
        // only state changes matter (a connection going up or down)
        if (c.state() & QNetworkConfiguration::Active || c.state() == QNetworkConfiguration::Discovered)
            debounce->start();
    });
}

inline void keepNetworkAccessible(QNetworkAccessManager *manager)
{
    {
        QMutexLocker lock(&networkFixMutex());
        networkFixManagers().append(QPointer<QNetworkAccessManager>(manager));
    }

    manager->setNetworkAccessible(QNetworkAccessManager::Accessible);
    QObject::connect(manager, &QNetworkAccessManager::networkAccessibleChanged, manager,
                     [manager](QNetworkAccessManager::NetworkAccessibility accessible) {
        manager->clearAccessCache();
        if (accessible != QNetworkAccessManager::Accessible)
            manager->setNetworkAccessible(QNetworkAccessManager::Accessible);
    });
}

class NetworkFixFactory : public QQmlNetworkAccessManagerFactory
{
public:
    QNetworkAccessManager *create(QObject *parent) override
    {
        QNetworkAccessManager *manager = new QNetworkAccessManager(parent);
        keepNetworkAccessible(manager);
        return manager;
    }
};

#endif // NETWORKFIX_H
