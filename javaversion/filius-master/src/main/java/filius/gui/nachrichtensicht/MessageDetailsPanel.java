/*
 ** This file is part of Filius, a network construction and simulation software.
 ** 
 ** Originally created at the University of Siegen, Institute "Didactics of
 ** Informatics and E-Learning" by a students' project group:
 **     members (2006-2007): 
 **         André Asschoff, Johannes Bade, Carsten Dittich, Thomas Gerding,
 **         Nadja Haßler, Ernst Johannes Klebert, Michell Weyer
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
import java.awt.Font;
import java.awt.FontMetrics;
import java.io.BufferedReader;
import java.io.IOException;
import java.io.StringReader;

import javax.swing.BorderFactory;
import javax.swing.Box;
import javax.swing.BoxLayout;
import javax.swing.JLabel;
import javax.swing.JPanel;
import javax.swing.JTextArea;
import javax.swing.JTree;
import javax.swing.SwingUtilities;
import javax.swing.UIManager;
import javax.swing.plaf.ColorUIResource;
import javax.swing.tree.DefaultMutableTreeNode;
import javax.swing.tree.TreeCellRenderer;

import filius.rahmenprogramm.nachrichten.Lauscher;

/**
 * Not used anymore, since this presentation of the message details was replaced with class MessageDetailsTable.
 */
public class MessageDetailsPanel extends MessageDetails {
    private String macAddress;

    public MessageDetailsPanel(String macAddress) {
        this.macAddress = macAddress;
        this.setLayout(new BorderLayout());
        this.setBackground(Color.WHITE);
    }

    public void clear() {
        removeAll();
        updateUI();
    }

    public void update(String interfaceId, int frameNumber) {
        Object[][] daten = Lauscher.getLauscher().getDaten(macAddress, false, 0);
        int dataSetNo = 0;
        int currNo = 0;
        for (; dataSetNo < daten.length; dataSetNo++) {
            currNo = Integer.parseInt(daten[dataSetNo][0].toString());
            if (currNo == frameNumber)
                break;
        }

        Object[] dataSet = daten[dataSetNo];
        DefaultMutableTreeNode rootNode = new DefaultMutableTreeNode(
                AggregatedExchangePanel.messages.getString("rp_lauscher_msg1") + ": " + dataSet[0] + " / "
                        + AggregatedExchangePanel.messages.getString("rp_lauscher_msg2") + ": " + dataSet[1]);
        for (; dataSetNo < daten.length
                && Integer.parseInt(daten[dataSetNo][0].toString()) == frameNumber; dataSetNo++) {
            dataSet = daten[dataSetNo];
            DefaultMutableTreeNode layerNode = new DefaultMutableTreeNode(dataSet[5], true);
            DefaultMutableTreeNode dateNode;
            DefaultMutableTreeNode labelNode;
            if (dataSet[2] != null && !dataSet[2].toString().isEmpty()) {
                String srcLabel = String.format("%-15s",
                        AggregatedExchangePanel.messages.getString("rp_lauscher_msg3") + ": ");
                dateNode = new DefaultMutableTreeNode(srcLabel + dataSet[2]);
                layerNode.add(dateNode);
            }
            if (dataSet[3] != null && !dataSet[3].toString().isEmpty()) {
                String destLabel = String.format("%-15s",
                        AggregatedExchangePanel.messages.getString("rp_lauscher_msg4") + ": ");
                dateNode = new DefaultMutableTreeNode(destLabel + dataSet[3]);
                layerNode.add(dateNode);
            }
            if (dataSet[4] != null && !dataSet[4].toString().isEmpty()) {
                String protocolLabel = String.format("%-15s",
                        AggregatedExchangePanel.messages.getString("rp_lauscher_msg5") + ": ");
                dateNode = new DefaultMutableTreeNode(protocolLabel + dataSet[4]);
                layerNode.add(dateNode);
            }
            if (dataSet[6] != null && !dataSet[6].toString().isEmpty()) {
                String contentLabel = AggregatedExchangePanel.messages.getString("rp_lauscher_msg7");
                if (dataSet[5] == Lauscher.PROTOKOLL_SCHICHTEN[3]) {
                    contentLabel += " (" + dataSet[6].toString().length() + " Bytes)";
                }
                contentLabel += ": ";
                if (dataSet[6].toString().contains("\n") || dataSet[6].toString().length() > 60) {
                    labelNode = new DefaultMutableTreeNode(contentLabel);
                    dateNode = new DefaultMutableTreeNode(dataSet[6]);
                    labelNode.add(dateNode);
                    layerNode.add(labelNode);
                } else {
                    dateNode = new DefaultMutableTreeNode(String.format("%-15s", contentLabel) + dataSet[6]);
                    layerNode.add(dateNode);
                }
            }
            rootNode.add(layerNode);
        }
        JTree detailsTree = new JTree(rootNode);
        for (int i = 0; i < detailsTree.getRowCount(); i++) {
            detailsTree.expandRow(i);
        }
        detailsTree.setCellRenderer(new MultiLineCellRenderer());
        this.removeAll();
        this.add(detailsTree, BorderLayout.WEST);
        this.updateUI();
    }

    // This code is based on an example published at
    // http://www.java2s.com/Code/Java/Swing-Components/MultiLineTreeExample.htm
    class MultiLineCellRenderer extends JPanel implements TreeCellRenderer {
        protected JLabel icon;

        protected TreeTextArea text;

        public MultiLineCellRenderer() {
            setLayout(new BoxLayout(this, BoxLayout.LINE_AXIS));
            icon = new JLabel() {
                public void setBackground(Color color) {
                    if (color instanceof ColorUIResource)
                        color = null;
                    super.setBackground(color);
                }
            };
            add(icon);
            add(Box.createHorizontalStrut(4));
            add(text = new TreeTextArea());
        }

        public Component getTreeCellRendererComponent(JTree tree, Object value, boolean isSelected, boolean expanded,
                boolean leaf, int row, boolean hasFocus) {
            String stringValue = tree.convertValueToText(value, isSelected, expanded, leaf, row, hasFocus);
            setEnabled(tree.isEnabled());
            text.setText(stringValue);
            text.setSelect(isSelected);
            text.setFocus(hasFocus);
            return this;
        }

        public Dimension getPreferredSize() {
            Dimension iconD = icon.getPreferredSize();
            Dimension textD = text.getPreferredSize();
            int height = iconD.height < textD.height ? textD.height : iconD.height;
            return new Dimension(iconD.width + textD.width, height);
        }

        public void setBackground(Color color) {
            if (color instanceof ColorUIResource)
                color = null;
            super.setBackground(color);
        }

        class TreeTextArea extends JTextArea {
            Dimension preferredSize;

            TreeTextArea() {
                setLineWrap(true);
                setWrapStyleWord(true);
                setOpaque(true);
                Font font = getFont();
                setFont(new Font(Font.MONOSPACED, Font.BOLD, font.getSize()));
            }

            public void setBackground(Color color) {
                if (color instanceof ColorUIResource)
                    color = null;
                super.setBackground(color);
            }

            public void setPreferredSize(Dimension d) {
                if (d != null) {
                    preferredSize = d;
                }
            }

            public Dimension getPreferredSize() {
                return preferredSize;
            }

            public void setText(String str) {
                Font font = getFont();
                FontMetrics fm = getToolkit().getFontMetrics(font);
                BufferedReader br = new BufferedReader(new StringReader(str));
                String line;
                int maxWidth = 0, lines = 0;
                try {
                    while ((line = br.readLine()) != null) {
                        int width = SwingUtilities.computeStringWidth(fm, line);
                        if (maxWidth < width) {
                            maxWidth = width;
                        }
                        lines++;
                    }
                } catch (IOException ex) {
                    ex.printStackTrace();
                }
                lines = (lines < 1) ? 1 : lines;
                int height = fm.getHeight() * lines;
                setPreferredSize(new Dimension(maxWidth + 12, height));
                super.setText(str);
            }

            void setSelect(boolean isSelected) {
                Color bColor;
                if (isSelected) {
                    bColor = UIManager.getColor("Tree.selectionBackground");
                } else {
                    bColor = UIManager.getColor("Tree.textBackground");
                }
                super.setBackground(bColor);
            }

            void setFocus(boolean hasFocus) {
                if (hasFocus) {
                    Color lineColor = UIManager.getColor("Tree.selectionBorderColor");
                    setBorder(BorderFactory.createLineBorder(lineColor));
                } else {
                    setBorder(BorderFactory.createEmptyBorder(1, 1, 1, 1));
                }
            }
        }
    }
}