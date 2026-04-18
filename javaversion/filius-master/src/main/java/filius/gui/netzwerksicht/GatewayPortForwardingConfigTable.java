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

import java.awt.Component;
import java.util.regex.Pattern;

import javax.swing.event.ChangeEvent;
import javax.swing.table.DefaultTableModel;
import javax.swing.table.TableCellEditor;
import javax.swing.table.TableCellRenderer;
import javax.swing.table.TableModel;

import filius.gui.JExtendedTable;
import filius.rahmenprogramm.EingabenUeberpruefung;
import filius.rahmenprogramm.I18n;
import filius.software.vermittlungsschicht.IpPaket;

@SuppressWarnings("serial")
public class GatewayPortForwardingConfigTable extends JExtendedTable implements I18n {

    public GatewayPortForwardingConfigTable(TableModel model, boolean editable) {
        super(model, editable);
    }

    public void editingStopped(ChangeEvent evt) {
        closeEditor();
    }

    void closeEditor() {
        TableCellEditor editor = getCellEditor();
        if (editor != null) {
    		String data = (String) getCellEditor().getCellEditorValue();
        	setValueAt(data,editingRow,editingColumn);
            ((JPortForwardingDialog) parentGUI).addEintrag(getCurrentValueAt(editingRow, 0), getCurrentValueAt(editingRow, 1), getCurrentValueAt(editingRow, 2), getCurrentValueAt(editingRow, 3));
            removeEditor();
        }
        ((JPortForwardingDialog) parentGUI).aenderungenAnnehmen();
        ((DefaultTableModel) getModel()).fireTableDataChanged();
    }

    private String getCurrentValueAt(int row, int col) {
        if (row == editingRow && col == editingColumn) {
        	String data = null;
        	if (col == 0) {
        		switch(((String) getCellEditor().getCellEditorValue()).toUpperCase()) {
                case "TCP":
                	data = ""+IpPaket.TCP;
                	break;
                case "UDP":
                	data = ""+IpPaket.UDP;
                	break;
                }
        	} else {
        		data = (String) getCellEditor().getCellEditorValue();
        	}
        	return data;
        } else {
        	return (String) getValueAt(row, col);
        }
    }
    
    public Component prepareRenderer(TableCellRenderer renderer, int row, int col) {
        Component comp = super.prepareRenderer(renderer, row, col);
        String cellValue = (String) getModel().getValueAt(row, col);
        Pattern pattern = null;
        switch (col) {
        case 0:
            pattern = EingabenUeberpruefung.musterProtocol;
            break;
        case 1:
            pattern = EingabenUeberpruefung.musterPort;
            break;
        case 2:
            pattern = EingabenUeberpruefung.musterIpAdresse;
            break;
        case 3:
            pattern = EingabenUeberpruefung.musterPort;
            break;
        }
        if (null != cellValue && EingabenUeberpruefung.isGueltig(cellValue, pattern)) {
            comp.setForeground(EingabenUeberpruefung.farbeRichtig);
        } else {
            comp.setForeground(EingabenUeberpruefung.farbeFalsch);
        }
        return comp;
    }
}
