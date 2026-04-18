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

import java.awt.Color;
import java.awt.Dimension;
import java.awt.FileDialog;
import java.awt.Point;
import java.awt.event.MouseEvent;
import java.io.File;
import java.io.FileOutputStream;
import java.io.FilenameFilter;
import java.io.IOException;
import java.io.OutputStream;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.Vector;

import javax.swing.JCheckBoxMenuItem;
import javax.swing.JMenuItem;
import javax.swing.JOptionPane;
import javax.swing.JPopupMenu;
import javax.swing.JScrollPane;
import javax.swing.JTable;
import javax.swing.ListSelectionModel;
import javax.swing.event.ChangeEvent;
import javax.swing.event.ChangeListener;
import javax.swing.event.MouseInputAdapter;
import javax.swing.table.DefaultTableColumnModel;
import javax.swing.table.DefaultTableModel;
import javax.swing.table.TableColumn;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.gui.JMainFrame;
import filius.gui.schichtensicht.GlobalLayerPath;
import filius.gui.schichtensicht.LayerPathDialog;
import filius.gui.schichtensicht.LocalLayerPathPanel;
import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.Information;
import filius.rahmenprogramm.SzenarioVerwaltung;
import filius.rahmenprogramm.nachrichten.Lauscher;
import filius.rahmenprogramm.nachrichten.LauscherBeobachter;
import filius.software.netzzugangsschicht.Ethernet;
import filius.software.system.SystemSoftware;

public class AggregatedMessageTable extends JTable implements LauscherBeobachter, I18n {
    private static Logger LOG = LoggerFactory.getLogger(AggregatedMessageTable.class);

    private static final int EXPORT_MAX_LINES_PER_MESSAGE = 5;

    private static final long serialVersionUID = 1L;

    /** Index der Spalte, in der die Schicht des Protokollschichtenmodells steht */
    public static final int SCHICHT_SPALTE = 5;
    public static final int BEMERKUNG_SPALTE = 6;
    public static final int LFD_NR_SPALTE = 0;

    private SystemSoftware systemSoftware;

    private String interfaceId;

    private int selectedRowByRightclick;

    private JCheckBoxMenuItem checkbox;

    private AggregatedExchangeComponent exchangeComponent;
    private JScrollPane scrollPane = null;
    private boolean autoscroll = true;
    private JPopupMenu menu;

    public AggregatedMessageTable(AggregatedExchangeComponent component, String macAddress,
            SystemSoftware systemSoftware) {
        super();

        TableColumn col;
        DefaultTableColumnModel columnModel;

        this.systemSoftware = systemSoftware;
        this.exchangeComponent = component;
        setinterfaceId(macAddress);

        this.initTableModel();

        this.setAutoResizeMode(JTable.AUTO_RESIZE_LAST_COLUMN);

        columnModel = new DefaultTableColumnModel();
        String[] spalten = Lauscher.SPALTEN;
        for (int i = 0; i < spalten.length; i++) {
            col = new TableColumn();
            col.setHeaderValue(spalten[i]);
            col.setIdentifier(spalten[i]);
            col.setModelIndex(i);
            columnModel.addColumn(col);
        }

        this.setColumnModel(columnModel);

        this.setIntercellSpacing(new Dimension(0, 5));
        this.setRowHeight(25);
        this.setEnabled(true);
        this.setSelectionMode(ListSelectionModel.SINGLE_SELECTION);
        this.setShowGrid(false);
        this.setColumnSelectionAllowed(false);
        this.setBackground(Color.DARK_GRAY);
        this.getTableHeader().setReorderingAllowed(false);
        this.setFillsViewportHeight(true);

        initTableColumnWidth();
        this.setDefaultRenderer(Object.class, new LauscherTableCellRenderer());
        initKontextMenue();

        this.addMouseListener(new MouseInputAdapter() {
            public void mousePressed(MouseEvent e) {
                if (e.getButton() == 3) {
                    AggregatedMessageTable target = (AggregatedMessageTable) e.getSource();
                    target.selectedRowByRightclick = target.rowAtPoint(e.getPoint());

                    // Falls der Rechtsklick im leeren Bereich gemacht wurde
                    if (target.selectedRowByRightclick == -1) {
                        disablePathOptions();
                    } else {
                        target.setRowSelectionInterval(target.selectedRowByRightclick, target.selectedRowByRightclick);
                        enablePathOptions();
                    }

                    menu.setVisible(true);
                    menu.show(getTabelle(), e.getX(), e.getY());
                }
            }
        });

        update();
    }

    private void initTableModel() {
        LauscherTableModel tableModel = new LauscherTableModel();
        tableModel.addTableModelListener(this);
        tableModel.setColumnIdentifiers(Lauscher.SPALTEN);
        this.setModel(tableModel);
    }

    public void setScrollPane(JScrollPane scrollPane) {
        this.scrollPane = scrollPane;
    }

    private AggregatedMessageTable getTabelle() {
        return this;
    }

    private void initTableColumnWidth() {

        this.getColumnModel().getColumn(0).setMaxWidth(40);
        this.getColumnModel().getColumn(0).setPreferredWidth(30);
        this.getColumnModel().getColumn(1).setMaxWidth(120);
        this.getColumnModel().getColumn(1).setPreferredWidth(90);
        this.getColumnModel().getColumn(2).setMaxWidth(180);
        this.getColumnModel().getColumn(2).setPreferredWidth(160);
        this.getColumnModel().getColumn(3).setMaxWidth(180);
        this.getColumnModel().getColumn(3).setPreferredWidth(160);
        this.getColumnModel().getColumn(4).setMaxWidth(100);
        this.getColumnModel().getColumn(4).setPreferredWidth(70);
        this.getColumnModel().getColumn(5).setMaxWidth(140);
        this.getColumnModel().getColumn(5).setPreferredWidth(100);
        this.getColumnModel().getColumn(6).setMaxWidth(Integer.MAX_VALUE);
        this.getColumnModel().getColumn(6).setPreferredWidth(460);
        this.getColumnModel().getColumn(6).setResizable(true);
    }

    private int initKontextMenue() {
        menu = new JPopupMenu();
        AggregatedMessageTable target = this;

        if (Information.getInformation().isLayerVisualization()) {
            /*
             * JMenuItem localPathThroughLayersMenuItem = new JMenuItem(messages.getString("nachrichtentabelle_msg10"));
             * localPathThroughLayersMenuItem.addMouseListener(new MouseInputAdapter() { public void
             * mousePressed(MouseEvent e) { if (isPathOptionsEnabled()) { menu.setVisible(false);
             * showLocalPathThroughLayers(systemSoftware, target.selectedRowByRightclick + 1); } } });
             * menu.add(localPathThroughLayersMenuItem);
             */

            JMenuItem globalPathThroughLayersMenuItem = new JMenuItem(messages.getString("nachrichtentabelle_msg11"));
            globalPathThroughLayersMenuItem.addMouseListener(new MouseInputAdapter() {
                public void mousePressed(MouseEvent e) {
                    if (isPathOptionsEnabled()) {
                        menu.setVisible(false);
                        showGlobalPathThroughLayers(systemSoftware, target.selectedRowByRightclick + 1);
                    }
                }
            });
            menu.add(globalPathThroughLayersMenuItem);
        }

        JMenuItem resetMenuItem = new JMenuItem(messages.getString("nachrichtentabelle_msg7"));
        resetMenuItem.addMouseListener(new MouseInputAdapter() {
            public void mousePressed(MouseEvent e) {
                menu.setVisible(false);
                Lauscher.getLauscher().reset();
            }
        });
        menu.add(resetMenuItem);

        JMenuItem exportMenuItem = new JMenuItem(messages.getString("nachrichtentabelle_msg9"));
        exportMenuItem.addMouseListener(new MouseInputAdapter() {
            public void mousePressed(MouseEvent e) {
                menu.setVisible(false);

                FileDialog fileDialog = new FileDialog(JMainFrame.getJMainFrame(), messages.getString("main_msg4"),
                        FileDialog.SAVE);
                FilenameFilter filiusFilenameFilter = (dir, name) -> name.endsWith(".txt");
                fileDialog.setFilenameFilter(filiusFilenameFilter);

                String path = SzenarioVerwaltung.getInstance().holePfad();
                if (path != null) {
                    File preselectedFile = new File(
                            exchangeComponent.getTabTitle(AggregatedMessageTable.this.interfaceId) + ".txt");
                    fileDialog.setFile(preselectedFile.toString());
                }

                fileDialog.setVisible(true);
                if (fileDialog.getFile() != null) {
                    Path outFile;
                    boolean nameChanged = false;
                    if (StringUtils.endsWith(fileDialog.getFile(), ".txt")) {
                        outFile = Path.of(fileDialog.getDirectory(), fileDialog.getFile());
                    } else {
                        nameChanged = true;
                        outFile = Path.of(fileDialog.getDirectory(), fileDialog.getFile() + ".txt");
                    }
                    int entscheidung = JOptionPane.YES_OPTION;
                    if (nameChanged && outFile.toFile().exists()) {
                        entscheidung = JOptionPane.showConfirmDialog(JMainFrame.getJMainFrame(),
                                messages.getString("guimainmemu_msg17"), messages.getString("guimainmemu_msg10"),
                                JOptionPane.YES_NO_OPTION);
                    }
                    if (entscheidung == JOptionPane.YES_OPTION) {
                        try (FileOutputStream outputStream = new FileOutputStream(outFile.toString())) {
                            writeToStream(outputStream);
                        } catch (IOException e1) {}
                    }
                }
            }
        });
        menu.add(exportMenuItem);

        checkbox = new JCheckBoxMenuItem(messages.getString("nachrichtentabelle_msg8"), autoscroll);
        checkbox.addChangeListener(new ChangeListener() {
            public void stateChanged(ChangeEvent e) {
                if (autoscroll != checkbox.getState()) {
                    menu.setVisible(false);
                    autoscroll = checkbox.getState();
                    update();
                }
            }
        });
        menu.add(checkbox);

        menu.setVisible(false);
        exchangeComponent.getRootPane().getLayeredPane().add(menu);

        return menu.getComponentCount();
    }

    // activate context menu entries "lokaler Weg ..." and "globaler Weg ..."
    private void enablePathOptions() {
        if (!menu.getComponent(0).isEnabled() && !menu.getComponent(1).isEnabled()) {
            menu.getComponent(0).setEnabled(true);
            menu.getComponent(1).setEnabled(true);
        }
    }

    // deactivate context menu entries "lokaler Weg ..." and "globaler Weg ..."
    private void disablePathOptions() {
        if (menu.getComponent(0).isEnabled() && menu.getComponent(1).isEnabled()) {
            menu.getComponent(0).setEnabled(false);
            menu.getComponent(1).setEnabled(false);
        }
    }

    private boolean isPathOptionsEnabled() {
        return menu.getComponent(0).isEnabled() && menu.getComponent(1).isEnabled();
    }

    private void setinterfaceId(String interfaceId) {
        this.interfaceId = interfaceId;

        Lauscher.getLauscher().addBeobachter(interfaceId, this);
    }

    @Override
    public synchronized void update() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + " (NachrichtenTabelle), update()");

        int selectedRow = getSelectedRow();
        Object[][] daten = Lauscher.getLauscher().getDaten(interfaceId, true, 0);

        if (daten.length == 0) {
            initTableModel();
            initTableColumnWidth();
        }
        int lastNo = -1;
        if (getModel().getRowCount() > 0) {
            lastNo = Integer.parseInt(this.getModel().getValueAt(this.getModel().getRowCount() - 1, 0).toString());
        }

        int currentNo = 1;
        int previousNo = 1;
        for (int i = 0; i < daten.length; i++) {
            currentNo = Integer.parseInt(daten[i][0].toString());
            if (currentNo <= lastNo || currentNo == previousNo) {
                continue;
            }

            if (currentNo > previousNo && previousNo > lastNo && i > 0) {
                Object[] row = daten[i - 1];
                addRowData(row);
                previousNo = currentNo;
            }
        }
        if (currentNo > lastNo && daten.length > 0) {
            addRowData(daten[daten.length - 1]);
        }

        ((DefaultTableModel) this.getModel()).fireTableDataChanged();
        if (getModel().getRowCount() > 0 && scrollPane != null && scrollPane.getViewport() != null && autoscroll) {
            scrollPane.getViewport().setViewPosition(new Point(0, this.getHeight()));
        }
        if (selectedRow >= 0 && selectedRow < getModel().getRowCount()) {
            setRowSelectionInterval(selectedRow, selectedRow);
        }
    }

    private void addRowData(Object[] row) {
        Vector<Object> rowData = new Vector<Object>(row.length);
        for (int col = 0; col < row.length; col++) {
            rowData.add(col, row[col]);
        }
        ((DefaultTableModel) this.getModel()).addRow(rowData);
    }

    @Override
    public synchronized void writeToStream(OutputStream outputStream) throws IOException {
        String rowTemplate;
        String lineSeparator;

        Object[] columnNames = getColumnHeader();
        StringBuilder tmplBuilder = new StringBuilder("| ");
        StringBuilder lineSeparatorBuilder = new StringBuilder("+");
        for (int colIdx = 0; colIdx < getColumnCount(); colIdx++) {
            if (colIdx == BEMERKUNG_SPALTE) {
                tmplBuilder.append("%-40s | ");
                lineSeparatorBuilder.append(StringUtils.repeat('-', 42) + "+");
            } else if (colIdx == LFD_NR_SPALTE) {
                tmplBuilder.append("%-10s | ");
                lineSeparatorBuilder.append(StringUtils.repeat('-', 12) + "+");
            } else {
                tmplBuilder.append("%-20s | ");
                lineSeparatorBuilder.append(StringUtils.repeat('-', 22) + "+");
            }
        }
        tmplBuilder.append("\r\n");
        rowTemplate = tmplBuilder.toString();
        lineSeparatorBuilder.append("\r\n");
        lineSeparator = lineSeparatorBuilder.toString();

        outputStream.write(lineSeparator.replace('-', '=').getBytes("UTF8"));
        outputStream.write(String.format(rowTemplate, columnNames).getBytes("UTF8"));
        outputStream.write(lineSeparator.replace('-', '=').getBytes("UTF8"));

        for (int rowIndex = 0; rowIndex < getRowCount(); rowIndex++) {
            String[] values = new String[getColumnCount()];
            for (int columnIndex = 0; columnIndex < getColumnCount(); columnIndex++) {
                values[columnIndex] = getModel().getValueAt(rowIndex, columnIndex).toString();
            }
            List<String[]> lineData = prepareDataArrays(values, 40);
            for (String[] data : lineData) {
                outputStream.write(String.format(rowTemplate, (Object[]) data).getBytes("UTF8"));
            }
            outputStream.write(lineSeparator.getBytes("UTF8"));
        }
    }

    public Object[] getColumnHeader() {
        Object[] columnNames = new Object[getColumnCount()];
        for (int colIdx = 0; colIdx < getColumnCount(); colIdx++) {
            columnNames[colIdx] = getColumnName(colIdx);
        }
        return columnNames;
    }

    static List<String[]> prepareDataArrays(String[] values, int maxRemarkLength) {
        List<String> remarks = Collections.<String> emptyList();
        String[] data = new String[values.length];
        for (int columnIndex = 0; columnIndex < values.length; columnIndex++) {
            if (columnIndex == BEMERKUNG_SPALTE) {
                if (StringUtils.isNoneBlank(values[columnIndex])) {
                    remarks = splitString(values[columnIndex].toString(), maxRemarkLength);
                    data[columnIndex] = remarks.get(0);
                }
            } else {
                data[columnIndex] = values[columnIndex];
            }
        }
        List<String[]> lineData = new ArrayList<String[]>();
        lineData.add(data);
        for (int i = 1; i < remarks.size() && i < EXPORT_MAX_LINES_PER_MESSAGE; i++) {
            data = new String[values.length];
            Arrays.fill(data, StringUtils.EMPTY);
            data[BEMERKUNG_SPALTE] = remarks.get(i);
            lineData.add(data);
        }
        if (remarks.size() > EXPORT_MAX_LINES_PER_MESSAGE) {
            data = new String[values.length];
            Arrays.fill(data, StringUtils.EMPTY);
            data[BEMERKUNG_SPALTE] = "...";
            lineData.add(data);
        }
        return lineData;
    }

    /**
     * Original Filius colors for the different layers.
     */
    public enum LayerColorOrig {
        DEFAULT(Color.WHITE, Color.GRAY), LINK(Color.BLACK, new Color(0.9f, 0.9f, 0.9f)), INTERNET(Color.BLACK,
                new Color(0.3f, 1f, 0.3f)), TRANSPORT(Color.BLACK, Color.CYAN), APPLICATION(Color.WHITE, Color.BLUE);

        public final Color foregroundColor;
        public final Color backgroundColor;

        private LayerColorOrig(Color foregroundColor, Color backgroundColor) {
            this.foregroundColor = foregroundColor;
            this.backgroundColor = backgroundColor;
        }
    }

    /**
     * Color variants for the different layers.
     * 
     * @author Christoph Irniger
     */
    public enum LayerColorVar {
        DEFAULT(Color.BLACK, Color.decode("#A6A6A6"), Color.WHITE, Color.WHITE, Color.WHITE), LINK(Color.BLACK,
                Color.decode("#A6A6A6"), Color.decode("#C9C9C9"), Color.decode("#DBDBDB"),
                Color.decode("#F2F2F2")), INTERNET(Color.BLACK, Color.decode("#A6A6A6"), Color.decode("#8FAADC"),
                        Color.decode("#B4C6E7"), Color.decode("#D9E2F3")), TRANSPORT(Color.BLACK,
                                Color.decode("#A6A6A6"), Color.decode("#F4B183"), Color.decode("#F7CAAC"),
                                Color.decode("#FBE4D5")), APPLICATION(Color.BLACK, Color.decode("#A6A6A6"),
                                        Color.decode("#FFD966"), Color.decode("#FFE599"), Color.decode("#FFF2CC"));

        public final Color foregroundColor;
        public final Color foregroundColorGreyedOut;
        public final Color backgroundColor;
        public final Color backgroundColorFine;
        public final Color backgroundColorUltraFine;

        private LayerColorVar(Color foregroundColor, Color foregroundColorGreyedOut, Color backgroundColor,
                Color backgroundColorFine, Color backgroundColorUltraFine) {
            this.foregroundColor = foregroundColor;
            this.foregroundColorGreyedOut = foregroundColorGreyedOut;
            this.backgroundColor = backgroundColor;
            this.backgroundColorFine = backgroundColorFine;
            this.backgroundColorUltraFine = backgroundColorUltraFine;
        }

        public static Color getLayerColorVar(String typeOfColor, int layerNumber) {
            String layerName = null;
            if (layerNumber == 1) {
                layerName = "LINK";
            } else if (layerNumber == 2) {
                layerName = "INTERNET";
            } else if (layerNumber == 3) {
                layerName = "TRANSPORT";
            } else if (layerNumber == 4) {
                layerName = "APPLICATION";
            }
            Color color = null;
            if (typeOfColor == "foregroundColor") {
                color = valueOf(layerName).foregroundColor;
            } else if (typeOfColor == "foregroundColorGreyedOut") {
                color = valueOf(layerName).foregroundColorGreyedOut;
            } else if (typeOfColor == "backgroundColor") {
                color = valueOf(layerName).backgroundColor;
            } else if (typeOfColor == "backgroundColorFine") {
                color = valueOf(layerName).backgroundColorFine;
            } else if (typeOfColor == "backgroundColorUltraFine") {
                color = valueOf(layerName).backgroundColorUltraFine;
            }
            return color;
        }
    }

    static List<String> splitString(String text, int maxLength) {
        String normalizedText = StringUtils.normalizeSpace(text);
        String[] tokens = normalizedText.split(" ");
        List<String> lines = new ArrayList<String>();
        int currentLength = 0;
        StringBuilder lineBuilder = new StringBuilder();
        for (String token : tokens) {
            if (currentLength + token.length() <= maxLength) {
                lineBuilder.append(token).append(" ");
                currentLength += token.length() + 1;
            } else if (token.length() > maxLength) {
                if (currentLength > 0) {
                    lines.add(lineBuilder.toString().trim());
                }
                String[] parts = token.split("(?<=\\G.{" + maxLength + "})");
                for (int i = 0; i < parts.length - 1; i++) {
                    lines.add(parts[i]);
                }
                lineBuilder = new StringBuilder(parts[parts.length - 1]).append(" ");
                currentLength = parts[parts.length - 1].length() + 1;
            } else {
                lines.add(lineBuilder.toString().trim());
                lineBuilder = new StringBuilder(token).append(" ");
                currentLength = token.length() + 1;
            }
        }
        lines.add(lineBuilder.toString().trim());
        return lines;
    }

    /**
     * Opens local view of the path through layers.
     * 
     * @param systemSoftware
     *            system software of the node
     * @param frameNumber
     *            number of the selected frame in the data exchange (starts with 1)
     * 
     * @author Christoph Irniger
     */
    private void showLocalPathThroughLayers(SystemSoftware systemSoftware, int frameNumber) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass()
                + " (AggregatedMessageTable), showLocalPathThroughLayers()");
        new LayerPathDialog(filius.gui.JMainFrame.getJMainFrame(), interfaceId, systemSoftware, frameNumber, null,
                true);
    }

    /**
     * Opens global view of the path through layers.
     * 
     * @param systemSoftware
     *            system software of the node
     * @param frameNumber
     *            number of the selected frame in the data exchange (starts with 1)
     * 
     * @author Christoph Irniger
     */
    private void showGlobalPathThroughLayers(SystemSoftware systemSoftware, int frameNumber) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass()
                + " (AggregatedMessageTable), showGlobalPathThroughLayers()");
        // if the frame was sent and destination MAC of the frame is broadcast, global
        // view is not possible
        if (LocalLayerPathPanel.isFrameSent(interfaceId, frameNumber) && Lauscher.getLauscher()
                .getFrame(interfaceId, frameNumber).getZielMacAdresse().equals(Ethernet.ETHERNET_BROADCAST)) {
            JOptionPane.showMessageDialog(JMainFrame.getJMainFrame(), messages.getString("nachrichtentabelle_msg12"));
        } else {
            new GlobalLayerPath(filius.gui.JMainFrame.getJMainFrame(), interfaceId, systemSoftware, frameNumber);
        }
    }
}