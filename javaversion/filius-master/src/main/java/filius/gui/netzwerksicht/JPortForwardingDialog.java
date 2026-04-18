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
package filius.gui.netzwerksicht;

import java.awt.Color;
import java.awt.Dimension;
import java.awt.event.ActionEvent;
import java.awt.event.ActionListener;
import java.util.LinkedList;
import java.util.Vector;
import javax.swing.Box;
import javax.swing.JButton;
import javax.swing.JDialog;
import javax.swing.JFrame;
import javax.swing.JScrollPane;
import javax.swing.ListSelectionModel;
import javax.swing.table.DefaultTableModel;
import javax.swing.table.TableColumnModel;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.gui.ComboBoxTableCellEditor;
import filius.rahmenprogramm.I18n;

public class JPortForwardingDialog extends JDialog implements I18n {
    private static Logger LOG = LoggerFactory.getLogger(JPortForwardingDialog.class);

    private static final long serialVersionUID = 1L;

    private static final Color TAB_COLOR = new Color(240, 240, 240);

    JPortForwardingDialog jpfd = null;
    private LinkedList<String[]> staticNat;
   
    private GatewayPortForwardingConfigTable staticTable;
    
    public JPortForwardingDialog(LinkedList<String[]> staticNat2, JFrame dummyFrame) {
        super(dummyFrame, messages.getString("jgatewayconfiguration_msg19"), true);
        LOG.trace("INVOKED-2 (" + this.hashCode() + ") " + getClass() + ", constr: JPortForwardingDialog(" + staticNat2 + ","
                + dummyFrame + ")");
        this.staticNat = staticNat2;
        jpfd = this;
        
        JScrollPane scrollPane;
        Box vBox, hBox;
        DefaultTableModel model;
        TableColumnModel columnModel;
        JButton button;
        vBox = Box.createVerticalBox();
        vBox.add(Box.createVerticalStrut(10));

        hBox = Box.createHorizontalBox();
        hBox.add(Box.createHorizontalStrut(10));

        model = new DefaultTableModel(0, 4);
        staticTable = new GatewayPortForwardingConfigTable(model, true);
        staticTable.setParentGUI(this);
        staticTable.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        staticTable.setIntercellSpacing(new Dimension(10, 5));
        staticTable.setRowHeight(30);
        staticTable.setShowGrid(true);
        staticTable.setFillsViewportHeight(true);
        staticTable.setBackground(Color.WHITE);
        staticTable.setShowHorizontalLines(true);

        columnModel = staticTable.getColumnModel();
        columnModel.getColumn(0).setHeaderValue(messages.getString("jportforwarding_msg4"));
        String[] protValues = {"TCP","UDP"};
        columnModel.getColumn(0).setCellEditor(new ComboBoxTableCellEditor(protValues));
        columnModel.getColumn(1).setHeaderValue(messages.getString("jportforwarding_msg5"));
        columnModel.getColumn(2).setHeaderValue(messages.getString("jportforwarding_msg6"));
        columnModel.getColumn(3).setHeaderValue(messages.getString("jportforwarding_msg7"));
        columnModel.getColumn(0).setPreferredWidth(80);
        columnModel.getColumn(1).setPreferredWidth(60);
        columnModel.getColumn(2).setPreferredWidth(130);
        columnModel.getColumn(3).setPreferredWidth(60);

        scrollPane = new JScrollPane(staticTable);
        scrollPane.setPreferredSize(new Dimension(555, 300));

        vBox.add(scrollPane);
        vBox.add(Box.createVerticalStrut(10));

        hBox = Box.createHorizontalBox();
        hBox.add(Box.createHorizontalStrut(10));
        
        

        button = new JButton(messages.getString("jgatewayconfiguration_msg21"));
        button.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
                neuerEintrag();
            }

			
        });
        hBox.add(button);
        hBox.add(Box.createHorizontalStrut(10));

        button = new JButton(messages.getString("jgatewayconfiguration_msg22"));
        button.addActionListener(new ActionListener() {
            public void actionPerformed(ActionEvent e) {
            	markiertenEintragLoeschen();
            }
        });
        hBox.add(button);
        hBox.add(Box.createHorizontalStrut(10));

        vBox.add(hBox);
        vBox.add(Box.createVerticalStrut(10));
        
        getContentPane().add(vBox);
        getContentPane().setBackground(TAB_COLOR);

    }
    
    public void neuerEintrag() {
    	 LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", neuerEintrag()");
         aenderungenAnnehmen();

         Vector<String> eintrag = new Vector<String>();
         eintrag.addElement("TCP");
         eintrag.addElement("");
         eintrag.addElement("");
         eintrag.addElement("");

         ((DefaultTableModel) this.staticTable.getModel()).addRow(eintrag);

         this.staticTable.setRowSelectionInterval(this.staticTable.getModel().getRowCount() - 1, this.staticTable.getModel().getRowCount() - 1);
     }

    public void markiertenEintragLoeschen() {
        if (this.staticTable.getSelectedRow() > -1) {
            entferneEintrag(this.staticTable.getSelectedRow());
            aenderungenAnnehmen();
        }
    }

    private void entferneEintrag(int row) {
        ((DefaultTableModel) this.staticTable.getModel()).removeRow(row);
    }

    public void aenderungenAnnehmen() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", aenderungenAnnehmen()");
        Vector<Vector> tableData;

		if (this.staticTable.getCellEditor() != null) {
			this.staticTable.getCellEditor().stopCellEditing();
        }

        tableData = ((DefaultTableModel) this.staticTable.getModel()).getDataVector();
        
        staticNat.clear();
        for (int i = 0; i < tableData.size(); i++) {
            String[] portFordwardingEntry = extractRowData(i);
            addEintrag(portFordwardingEntry[0], portFordwardingEntry[1], portFordwardingEntry[2], portFordwardingEntry[3]);
        }
        updateAttribute();
    }

    private String[] extractRowData(int rowIdx) {
        Vector<Object> rowData = (Vector) ((DefaultTableModel) this.staticTable.getModel()).getDataVector().elementAt(rowIdx);
        String[] portFordwardingEntry = new String[rowData.size()];
        for (int j = 0; j < portFordwardingEntry.length; j++) {
        	portFordwardingEntry[j] = (String) rowData.elementAt(j);
        }
        return portFordwardingEntry;
    }

    public void updateAttribute() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", updateAttribute()");
        DefaultTableModel model;
        model = (DefaultTableModel) this.staticTable.getModel();
        
        model.setRowCount(0);
        this.createStaticTable();
        
        model.fireTableDataChanged();
    }

    public void createStaticTable() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", createStaticTable()");

        DefaultTableModel model = (DefaultTableModel) this.staticTable.getModel();
        for (int i = 0; i < staticNat.size(); i++) {
        	model.addRow(staticNat.get(i));
        }
    }

	public LinkedList<String[]> getStaticNATTable() {
		return staticNat;
	}

	public void addEintrag(String protocol, String port, String lanIp, String lanPort) {
		String[] data = new String[4];
		data[0] = protocol;
		data[1] = port;
		data[2] = lanIp;
		data[3] = lanPort;
		staticNat.add(data);
	}
}
