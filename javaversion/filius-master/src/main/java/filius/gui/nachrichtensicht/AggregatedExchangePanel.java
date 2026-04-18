/*
 ** This file is part of Filius, a network construction and simulation software.
 ** 
 ** Originally created at the University of Siegen, Institute "Didactics of
 ** Informatics and E-Learning" by a students' project group:
 **     members (2006-2007): 
 **         AndrÃ© Asschoff, Johannes Bade, Carsten Dittich, Thomas Gerding,
 **         Nadja HaÃŸler, Ernst Johannes Klebert, Michell Weyer
 **     supervisors:
 **         Stefan Freischlad (maintainer until 2009), Peer Stechert
 ** Project is maintained since 2010 by Christian Eibl <filius@c.fameibl.de>
 **         and Stefan Freischlad
 ** Filius is free software: you can redistribute it and/or modify
 ** it under the terms of the GNU General Public License as published by
 ** the Free Software Foundation, either version 2 of the License, or
 ** (at your option) version 3.
 ** 
 ** Filius is distributed in the hope that it will be useful,
 ** but WITHOUT ANY WARRANTY; without even the implied
 ** warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
 ** PURPOSE. See the GNU General Public License for more details.
 ** 
 ** You should have received a copy of the GNU General Public License
 ** along with Filius.  If not, see <http://www.gnu.org/licenses/>.
 */
package filius.gui.nachrichtensicht;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.Hashtable;
import java.util.Map.Entry;
import java.util.Observable;
import java.util.Observer;

import javax.swing.BorderFactory;
import javax.swing.JButton;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JScrollPane;
import javax.swing.JSplitPane;
import javax.swing.JTabbedPane;
import javax.swing.event.ListSelectionEvent;
import javax.swing.event.ListSelectionListener;
import javax.swing.plaf.basic.BasicButtonUI;

import filius.hardware.knoten.Host;
import filius.hardware.knoten.InternetKnoten;
import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.Information;
import filius.software.system.InternetKnotenBetriebssystem;
import filius.software.system.SystemSoftware;

/**
 * This class is used to show exchanged messages between components. Its functionality shall be akin to that of
 * wireshark.
 * 
 * @author stefan
 */
@SuppressWarnings({ "serial", "deprecation" })
public class AggregatedExchangePanel extends JTabbedPane implements AggregatedExchangeComponent, I18n, Observer {

    private Hashtable<String, JPanel> openedTabs = new Hashtable<String, JPanel>();
    private Hashtable<String, InternetKnotenBetriebssystem> systems = new Hashtable<String, InternetKnotenBetriebssystem>();
    private Hashtable<String, AggregatedMessageTable> tabellen = new Hashtable<String, AggregatedMessageTable>();

    /**
     * Diese Methode fuegt eine Tabelle hinzu
     */
    @Override
    public void addTable(SystemSoftware system, String identifier) {
        final AggregatedMessageTable tabelle;

        system.addObserver(this);
        final MessageDetails messageDetails;
        if (Information.getInformation().isLayerVisualization()) {
            messageDetails = new MessageDetailsTable(identifier, 0, Color.WHITE);
        } else {
            messageDetails = new MessageDetailsPanel(identifier);
        }

        if (openedTabs.get(identifier) == null) {
            tabelle = new AggregatedMessageTable(this, identifier, system);
            tabelle.getSelectionModel().addListSelectionListener(new ListSelectionListener() {

                @Override
                public void valueChanged(ListSelectionEvent e) {
                    if (tabelle.getSelectedRow() >= 0) {
                        messageDetails.update(identifier, tabelle.getSelectedRow() + 1);
                    } else {
                        messageDetails.clear();
                    }
                }
            });
            JPanel panel = new JPanel(new BorderLayout());

            JScrollPane scrollPane;
            scrollPane = new JScrollPane(tabelle);
            tabelle.setScrollPane(scrollPane);

            JSplitPane splitPane = new JSplitPane();
            // prevent the SplitPane to get user input (mainly to lock the divider)
            splitPane.setEnabled(false);
            splitPane.setDividerLocation(500);
            splitPane.setOrientation(JSplitPane.VERTICAL_SPLIT);
            splitPane.setTopComponent(scrollPane);
            splitPane.setBottomComponent(new JScrollPane(messageDetails));
            splitPane.setOneTouchExpandable(true);

            panel.add(splitPane, BorderLayout.CENTER);

            add(panel);
            setSelectedComponent(panel);

            TabTitle title = new TabTitle(this, identifier);
            setTabComponentAt(getSelectedIndex(), title);

            openedTabs.put(identifier, panel);
            systems.put(identifier, (InternetKnotenBetriebssystem) system);
            tabellen.put(identifier, tabelle);

            if (openedTabs.size() > 0) {
                setVisible(true);
            }

            updateTabTitle();
        } else {
            // if there is already a tab opened for this system set it to selected
            setSelectedComponent(openedTabs.get(identifier));
            tabellen.get(identifier).update();
        }
    }

    void updateTabTitle() {
        for (int i = 0; i < getTabCount(); i++) {
            for (String identifier : openedTabs.keySet()) {
                if (getComponentAt(i).equals(openedTabs.get(identifier))) {
                    SystemSoftware system = systems.get(identifier);
                    String ipAddress = ((InternetKnoten) system.getKnoten()).getNetzwerkInterfaceByMac(identifier)
                            .getIp();
                    String tabTitle;
                    if (system.getKnoten() instanceof Host && ((Host) system.getKnoten()).isUseIPAsName()) {
                        tabTitle = ipAddress;
                    } else {
                        tabTitle = system.getKnoten().holeAnzeigeName() + " - " + ipAddress;
                    }
                    TabTitle titlePanel = (TabTitle) getTabComponentAt(i);
                    titlePanel.setTitle(tabTitle);
                    break;
                }
            }
        }
    }

    void clearUnavailableComponents() {
        for (Entry<String, InternetKnotenBetriebssystem> system : systems.entrySet()) {
            if (!system.getValue().isStarted()) {
                removeTable(system.getKey());
            }
        }
    }

    private void removeTable(String mac) {
        removeTable(mac, openedTabs.get(mac));
    }

    @Override
    public void removeTable(String mac, JPanel panel) {
        if (mac != null) {
            openedTabs.remove(mac);
            tabellen.remove(mac);
            remove(panel);
            if (openedTabs.size() == 0) {
                setVisible(false);
            }

        }
    }

    public String getTabTitle(String interfaceId) {
        String title = interfaceId.replaceAll(":", "-");
        for (int i = 0; i < getTabCount(); i++) {
            Component tab = getComponentAt(i);
            if (tab == openedTabs.get(interfaceId)) {
                title = ((TabTitle) getTabComponentAt(i)).getTitle();
                break;
            }
        }
        return title;
    }

    @Override
    public void reset() {}

    private class TabTitle extends JPanel {
        private JLabel label;

        TabTitle(AggregatedExchangePanel parent, String identifier) {
            setOpaque(false);
            label = new JLabel();
            add(label, BorderLayout.WEST);
            JButton btnClose = new JButton("X");
            btnClose.setUI(new BasicButtonUI());
            btnClose.setForeground(Color.GRAY);
            btnClose.setBorder(BorderFactory.createEmptyBorder());
            btnClose.setPreferredSize(new Dimension(18, 18));
            btnClose.setToolTipText(messages.getString("buttontabcomponent_msg1"));
            add(btnClose, BorderLayout.EAST);
            btnClose.addActionListener(new ActionListener() {
                public void actionPerformed(ActionEvent evt) {
                    parent.removeTable(identifier);
                }
            });
        }

        void setTitle(String title) {
            label.setText(title);
        }

        String getTitle() {
            return label.getText();
        }
    }

    @Override
    public void update(Observable o, Object arg) {
        updateTabTitle();
    }
}
