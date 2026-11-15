/**
 * Shared pull-down menu (the standard Sailfish "pulley" menu at the top of
 * the page) used to move between the main pages of Hutspot.
 *
 * The entry of the current page is hidden. Page-specific entries declared
 * inside a NavigationPullDown instance are added below the navigation
 * entries, i.e. closest to the finger.
 *
 * License: MIT
 */

import QtQuick 2.2
import Sailfish.Silica 1.0

import "../Util.js" as Util

PullDownMenu {
    id: navMenu

    // objectName of the page the menu is in ("PlayingPage", "MyStuffPage", ...)
    property string currentPage: ""

    MenuItem {
        text: qsTr("About")
        onClicked: app.doSelectedMenuItem(Util.HutspotMenuItem.ShowAboutPage)
    }
    MenuItem {
        text: qsTr("Settings")
        onClicked: app.doSelectedMenuItem(Util.HutspotMenuItem.ShowSettingsPage)
    }
    MenuItem {
        text: qsTr("Devices")
        onClicked: app.doSelectedMenuItem(Util.HutspotMenuItem.ShowDevicesPage)
    }
    MenuItem {
        visible: currentPage !== "HistoryPage"
        text: qsTr("History")
        onClicked: app.showPage('HistoryPage')
    }
    MenuItem {
        visible: currentPage !== "TopStuffPage"
        text: qsTr("My Top")
        onClicked: app.showPage('TopStuffPage')
    }
    MenuItem {
        visible: currentPage !== "SearchPage"
        text: qsTr("Search")
        onClicked: app.showPage('SearchPage')
    }
    MenuItem {
        visible: currentPage !== "NewReleasePage"
        text: qsTr("Featured")
        onClicked: app.showPage('NewReleasePage')
    }
    MenuItem {
        visible: currentPage !== "MyStuffPage"
        text: qsTr("My Library")
        onClicked: app.showPage('MyStuffPage')
    }
    MenuItem {
        visible: currentPage !== "PlayingPage"
        text: qsTr("Now Playing")
        onClicked: app.showPage('PlayingPage')
    }
}
