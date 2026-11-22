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
#include <QQmlNetworkAccessManagerFactory>

inline void keepNetworkAccessible(QNetworkAccessManager *manager)
{
    manager->setNetworkAccessible(QNetworkAccessManager::Accessible);
    QObject::connect(manager, &QNetworkAccessManager::networkAccessibleChanged, manager,
                     [manager](QNetworkAccessManager::NetworkAccessibility accessible) {
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
