package filius.gui.nachrichtensicht;

import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.awt.Font;
import java.awt.GridBagConstraints;
import java.awt.GridBagLayout;
import java.util.HashSet;
import java.util.Set;

import javax.swing.BorderFactory;
import javax.swing.JLabel;
import javax.swing.JTextArea;
import javax.swing.SwingConstants;
import javax.swing.border.Border;
import javax.swing.border.CompoundBorder;
import javax.swing.border.EmptyBorder;
import javax.swing.border.EtchedBorder;

import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.nachrichten.Lauscher;

/**
 * Class for the colored message details table at the bottom of the data exchange and the layer views.
 * 
 * @author Christoph Irniger
 */
public class MessageDetailsTable extends MessageDetails implements I18n {
    private final GridBagLayout GRID_BAG_LAYOUT;
    private GridBagConstraints c;

    private static final int MSG_DETAILS_CELL_WIDTH = 150;
    private static final int MSG_DETAILS_CELL_HEIGHT = 30;

    private String interfaceId;
    /** starts with 1 */
    private int frameNumber;
    /** data for the graphical table */
    private String[][] messageDetailsMatrix;

    private int maxLayerInsideFrame;

    private Color backgroundColor;

    public MessageDetailsTable(String interfaceId, int frameNumber, Color backgroundColor) {
        GRID_BAG_LAYOUT = new GridBagLayout();
        c = new GridBagConstraints();
        this.interfaceId = interfaceId;
        this.frameNumber = frameNumber;
        this.backgroundColor = backgroundColor;

        setLayout(GRID_BAG_LAYOUT);
        setBackground(Color.WHITE);

        if (frameNumber >= 1) {
            update(interfaceId, frameNumber);
        }
    }

    public GridBagLayout getGridBagLayout() {
        return this.GRID_BAG_LAYOUT;
    }

    public int getMaxLayerInsideFrame() {
        return this.maxLayerInsideFrame;
    }

    @Override
    public Dimension getPreferredSize() {
        return getSizeOfMessageDetailsTable();
    }

    @Override
    public Dimension getMinimumSize() {
        return getSizeOfMessageDetailsTable();
    }

    @Override
    public Dimension getMaximumSize() {
        return getSizeOfMessageDetailsTable();
    }

    /**
     * Returns the size of the whole table based on the corresponding constants.
     * 
     * @return Dimension of the whole MessageDetailsTable
     */
    public static Dimension getSizeOfMessageDetailsTable() {
        return new Dimension(9 * MSG_DETAILS_CELL_WIDTH, 8 * MSG_DETAILS_CELL_HEIGHT);
    }

    /**
     * Fills the message details matrix with the values of the frame associated with the interface id and frame number.
     * The matrix will have an empty second line (e.g. messageDetails[1][...] is Null), such that it will match row and
     * column numbers of the MessageDetailsTable, which will be the graphical variant.
     */
    private void setMessageDetails() {
        Object[][] daten = Lauscher.getLauscher().getDaten(interfaceId, false, 0);
        String frameNumberAsString = Integer.toString(frameNumber);

        for (int i = 0; i < daten.length; i++) {
            if (daten[i][0].equals(frameNumberAsString)) {

                // -----Netzzugangs-Daten-----
                // Quelle
                messageDetailsMatrix[3][1] = daten[i][2].toString();
                // Ziel
                messageDetailsMatrix[4][1] = daten[i][3].toString();
                // Bemerkungen / Details
                messageDetailsMatrix[5][1] = daten[i][6].toString();

                // -----Vermittlungs-Daten (falls existent)-----
                if (i + 1 < daten.length && daten[i + 1][0].equals(frameNumberAsString)) {
                    // Protokoll
                    messageDetailsMatrix[2][2] = daten[i + 1][4].toString();
                    // Quelle
                    messageDetailsMatrix[3][3] = daten[i + 1][2].toString();
                    // Ziel
                    messageDetailsMatrix[4][3] = daten[i + 1][3].toString();
                    // Bemerkungen / Details
                    messageDetailsMatrix[5][3] = daten[i + 1][6].toString();

                    // -----Transport-Daten (falls existent)-----
                    if (i + 2 < daten.length && daten[i + 2][0].equals(frameNumberAsString)) {
                        // Protokoll
                        messageDetailsMatrix[2][4] = daten[i + 2][4].toString();
                        // Quelle
                        messageDetailsMatrix[3][5] = daten[i + 2][2].toString();
                        // Ziel
                        messageDetailsMatrix[4][5] = daten[i + 2][3].toString();
                        // Bemerkungen / Details
                        messageDetailsMatrix[5][5] = daten[i + 2][6].toString();

                        // -----Anwendungs-Daten (falls existent)-----
                        if (i + 3 < daten.length && daten[i + 3][0].equals(frameNumberAsString)) {
                            // Protokoll
                            messageDetailsMatrix[2][6] = daten[i + 3][4].toString();
                            // Daten
                            messageDetailsMatrix[3][6] = daten[i + 3][6].toString();
                        }
                        break;
                    } else {
                        break;
                    }
                } else {
                    break;
                }
            }
        }
    }

    /**
     * Computes the maximum layer inside which appears inside the frame.
     * 
     * @return maximum layer that appears inside the frame
     */
    private int computeMaxLayerInsideFrame() {
        int maxLayerInsideFrame = 1;

        // -----Vermittlung-----
        if (messageDetailsMatrix[2][2] != null) {
            maxLayerInsideFrame = 2;
            // -----Transport-----
            if (messageDetailsMatrix[2][4] != null) {
                maxLayerInsideFrame = 3;
                // -----Anwendung-----
                if (messageDetailsMatrix[2][6] != null) {
                    maxLayerInsideFrame = 4;
                }
            }
        }
        return maxLayerInsideFrame;
    }

    /**
     * Fills the message details matrix with the titles (column and cell labels) that are the same for both tables.
     * 
     * @param messageDetails
     *            the matrix which should be filled with the titles
     */
    private void setTitles() {
        // Netzzugang
        messageDetailsMatrix[0][0] = messages.getString("rp_lauscher_msg8");
        // Vermittlung
        messageDetailsMatrix[0][2] = messages.getString("rp_lauscher_msg9");
        // Transport
        messageDetailsMatrix[0][4] = messages.getString("rp_lauscher_msg10");
        // Anwendung
        messageDetailsMatrix[0][6] = messages.getString("rp_lauscher_msg11");
        // Ethernet
        messageDetailsMatrix[2][0] = messages.getString("schichten_lokaler_weg_msg5");
        // Quelle (Netzzugang)
        messageDetailsMatrix[3][0] = messages.getString("rp_lauscher_msg3") + ":";
        // Ziel (Netzzugang)
        messageDetailsMatrix[4][0] = messages.getString("rp_lauscher_msg4") + ":";
        // Bemerkungen / Details (Netzzugang)
        messageDetailsMatrix[5][0] = messages.getString("rp_lauscher_msg7") + ":";
        // Quelle (Vermittlung)
        messageDetailsMatrix[3][2] = messages.getString("rp_lauscher_msg3") + ":";
        // Ziel (Vermittlung)
        messageDetailsMatrix[4][2] = messages.getString("rp_lauscher_msg4") + ":";
        // Bemerkungen / Details (Vermittlung)
        messageDetailsMatrix[5][2] = messages.getString("rp_lauscher_msg7") + ":";
        if (maxLayerInsideFrame >= 3) {
            // Quelle (Transport)
            messageDetailsMatrix[3][4] = messages.getString("rp_lauscher_msg3") + ":";
            // Ziel (Transport)
            messageDetailsMatrix[4][4] = messages.getString("rp_lauscher_msg4") + ":";
            // Bemerkungen / Details (Transport)
            messageDetailsMatrix[5][4] = messages.getString("rp_lauscher_msg7") + ":";
        }
        // Schicht
        messageDetailsMatrix[0][7] = messages.getString("schichten_lokaler_weg_msg2");
        // Protokoll
        messageDetailsMatrix[2][7] = messages.getString("schichten_lokaler_weg_msg3");
        // Daten
        messageDetailsMatrix[3][7] = messages.getString("schichten_lokaler_weg_msg4");
    }

    /**
     * Initializes the graphical table without any text.
     */
    private void initializeTable() {
        // Storage for creating the Labels (cells with little content) and
        // TextAreas (cells with potential large content)
        JLabel label;
        JTextArea textArea;

        // first row (from left to right)
        for (int column = 0; column < 6; column = column + 2) {
            label = setLabel("", column, 0, 2, 1, 1, 1, false);
            label.setHorizontalAlignment(SwingConstants.CENTER);
            label.setBackground((getColorByColumn("backgroundColorFine", column)));
            label.setBorder(BorderFactory.createEtchedBorder(EtchedBorder.LOWERED));
            setBoldAndItalic(label);
        }
        label = setLabel("", 6, 0, 1, 1, 2, 1, false);
        label.setHorizontalAlignment(SwingConstants.CENTER);
        label.setBackground(getLayerColorVar("backgroundColorFine", 4));
        label.setBorder(BorderFactory.createEtchedBorder(EtchedBorder.LOWERED));
        setBoldAndItalic(label);
        label = setLabel("", 7, 0, 1, 1, 0.5, 1, false);
        label.setHorizontalAlignment(JLabel.CENTER);
        label.setVerticalAlignment(JLabel.CENTER);
        label.setBackground(backgroundColor);
        label.setBorder(BorderFactory.createEtchedBorder(EtchedBorder.LOWERED));
        setBoldAndItalic(label);

        // second empty row, which is transparent (from left to right)
        for (int column = 0; column < 6; column = column + 2) {
            label = setEmptyCell(column, 1, 2, 1, 1, 0.8);
        }
        label = setEmptyCell(6, 1, 1, 1, 2, 0.8);
        label = setEmptyCell(7, 1, 1, 1, 0.5, 0.8);

        // third row (from left to right)
        for (int column = 0; column < 6; column = column + 2) {
            label = setLabel("", column, 2, 2, 1, 1, 1, true);
            label.setHorizontalAlignment(SwingConstants.CENTER);
            label.setBackground((getColorByColumn("backgroundColor", column)));
        }
        label = setLabel("", 6, 2, 1, 1, 2, 1, true);
        label.setHorizontalAlignment(SwingConstants.CENTER);
        label.setBackground(getLayerColorVar("backgroundColor", 4));
        label = setLabel("", 7, 2, 1, 1, 0.5, 1, false);
        label.setHorizontalAlignment(JLabel.CENTER);
        label.setVerticalAlignment(JLabel.CENTER);
        label.setBackground(backgroundColor);
        label.setBorder(BorderFactory.createEtchedBorder(EtchedBorder.LOWERED));
        setBoldAndItalic(label);

        // fourth and fifth row, first to sixth columns (from left to right)
        for (int row = 3; row < 5; row++) {
            for (int column = 0; column < 6; column++) {
                label = setLabel("", column, row, 1, 1, 1, 1, true);
                if (column % 2 == 0) {
                    label.setHorizontalAlignment(SwingConstants.RIGHT);
                }
                label.setBackground((getColorByColumn("backgroundColor", column)));
            }
        }

        // sixth row, first to sixth columns (from left to right)
        for (int column = 0; column < 6; column++) {
            if (column % 2 == 0) {
                label = setLabel("", column, 5, 1, 1, 1, 3, true);
                label.setHorizontalAlignment(SwingConstants.RIGHT);
                label.setVerticalAlignment(SwingConstants.TOP);
                label.setBackground((getColorByColumn("backgroundColor", column)));
            } else {
                textArea = setTextArea("", column, 5, 1, 1, 1, 3);
                textArea.setBackground(getColorByColumn("backgroundColor", column));
            }
        }

        // last two cells on the bottom right with height 3
        textArea = setTextArea("", 6, 3, 1, 3, 2, 5 / 3.0);
        textArea.setBackground(getLayerColorVar("backgroundColor", 4));
        label = setLabel("", 7, 3, 1, 3, 0.5, 5 / 3.0, false);
        label.setHorizontalAlignment(JLabel.CENTER);
        label.setVerticalAlignment(JLabel.CENTER);
        label.setBackground(backgroundColor);
        label.setBorder(BorderFactory.createEtchedBorder(EtchedBorder.LOWERED));
        setBoldAndItalic(label);
    }

    /**
     * Updates this table with the values in the message details matrix.
     * 
     * @param interfaceId
     *            the interface id where the frame should be looked up
     * @param frameNumber
     *            the number of the frame in the data exchange of the interface (starts with 1)
     */
    public void update(String interfaceId, int frameNumber) {
        this.interfaceId = interfaceId;
        this.frameNumber = frameNumber;
        messageDetailsMatrix = new String[6][8];
        setMessageDetails();
        maxLayerInsideFrame = computeMaxLayerInsideFrame();
        setTitles();
        initializeTable();
        for (Component component : getComponents()) {
            int gridx = GRID_BAG_LAYOUT.getConstraints(component).gridx;
            int gridy = GRID_BAG_LAYOUT.getConstraints(component).gridy;
            String text = messageDetailsMatrix[gridy][gridx] != null ? messageDetailsMatrix[gridy][gridx] : "";
            if (component instanceof JLabel) {
                ((JLabel) component).setText(text);
            } else if (component instanceof JTextArea) {
                ((JTextArea) component).setText(text);
            }
        }
        setLayersInvisible();
    }

    /**
     * Sets the layers which are not needed invisible if they do not appear inside the frame.
     */
    public void setLayersInvisible() {
        // determine columns to deactivate
        Set<Integer> columns = new HashSet<>();
        if (maxLayerInsideFrame == 4) {
            return;
        } else if (maxLayerInsideFrame == 3) {
            columns.add(6); // application data
        } else if (maxLayerInsideFrame == 2) {
            columns.add(4); // transport data left side
            columns.add(5); // transport data right side
            columns.add(6); // application data
        }

        // deactivate columns
        for (Component component : getComponents()) {
            if (columns.contains(getGridBagLayout().getConstraints(component).gridx)) {
                component.setVisible(false);
            }
        }
    }

    /**
     * Remove all components from this container.
     */
    public void clear() {
        removeAll();
        updateUI();
    }

    /**
     * This method returns the color defined in the enum class LayerColorVar in class AggregatedMessageTable
     * corresponding to the type of color and the layer number.
     * 
     * @param typeOfColor
     *            All types of colors defined in the enum class in class AggregatedMessageTable: "foregroundColor",
     *            "backgroundColor", "backgroundColorFine", "backgroundColorUltraFine"
     * @param layerNumber
     *            number of the layer (1 = LINK, 2 = INTERNET, 3 = TRANSPORT, 4 = APPLICATION)
     * @return the desired color
     */
    public static Color getLayerColorVar(String typeOfColor, int layerNumber) {
        return AggregatedMessageTable.LayerColorVar.getLayerColorVar(typeOfColor, layerNumber);
    }

    /**
     * This method returns the color corresponding to the type of color and the layer which belongs to the column of the
     * MessageDetailsTable.
     * 
     * @param typeOfColor
     *            All types of colors defined in the enum class in class AggregatedMessageTable: "foregroundColor",
     *            "backgroundColor", "backgroundColorFine", "backgroundColorUltraFine"
     * @param column
     *            column of the MessageDetailsTable
     * @return the desired color
     */
    private Color getColorByColumn(String typeOfColor, int column) {
        Color color = null;
        if (column == 0 || column == 1) {
            color = getLayerColorVar(typeOfColor, 1);
        } else if (column == 2 || column == 3) {
            color = getLayerColorVar(typeOfColor, 2);
        } else if (column == 4 || column == 5) {
            color = getLayerColorVar(typeOfColor, 3);
        } else if (column == 6) {
            color = getLayerColorVar(typeOfColor, 4);
        }
        return color;
    }

    /**
     * Helper method to create a new JLabel in the GridBagLayout. JLabels are needed for one line content.
     * 
     * @return The JLabel
     */
    private JLabel setLabel(String text, int x_pos, int y_pos, int width, int height, double width_multiplier,
            double height_multiplier, boolean needsBorder) {
        JLabel label = new JLabel(text);

        setStandards(label, x_pos, y_pos, width, height, width_multiplier, height_multiplier);
        label.setOpaque(true);
        setPlain(label);

        if (needsBorder) {
            setBorderVisible(label, true);
        }
        add(label, c);

        return label;
    }

    /**
     * Helper method to create a new JTextArea in the GridBagLayout. JTextAreas are needed for multiline content.
     * 
     * @return The JTextArea
     */
    private JTextArea setTextArea(String text, int x_pos, int y_pos, int width, int height, double width_multiplier,
            double height_multiplier) {
        JTextArea textArea = new JTextArea(text);

        textArea.setOpaque(true);
        textArea.setWrapStyleWord(true);
        textArea.setLineWrap(true);
        textArea.setEditable(false);
        textArea.setFocusable(false);

        setBorderVisible(textArea, true);

        setStandards(textArea, x_pos, y_pos, width, height, width_multiplier, height_multiplier);
        add(textArea, c);

        return textArea;
    }

    /**
     * Helper method to create a visually empty cell, which is a JLabel, into the GridBagLayout. Empty cells form the
     * gap between the first and the third row.
     * 
     * @param x_pos
     * @param y_pos
     * @param width
     * @param height
     * @param width_multiplier
     * @param height_multiplier
     * @return The JLabel
     */
    private JLabel setEmptyCell(int x_pos, int y_pos, int width, int height, double width_multiplier,
            double height_multiplier) {
        JLabel label = new JLabel();

        label.setOpaque(false);

        label.setBorder(javax.swing.BorderFactory.createEmptyBorder());

        setStandards(label, x_pos, y_pos, width, height, width_multiplier, height_multiplier);
        add(label, c);

        return label;
    }

    /**
     * Helper method to set standard GridBagLayout constraints.
     * 
     * @param component
     * @param x_pos
     * @param y_pos
     * @param width
     * @param height
     * @param width_multiplier
     * @param height_multiplier
     */
    private void setStandards(Component component, int x_pos, int y_pos, int width, int height, double width_multiplier,
            double height_multiplier) {
        Dimension dimensionOfComponent = new Dimension((int) (width_multiplier * width * MSG_DETAILS_CELL_WIDTH),
                (int) (height_multiplier * height * MSG_DETAILS_CELL_HEIGHT));
        component.setPreferredSize(dimensionOfComponent);
        component.setMinimumSize(dimensionOfComponent);
        component.setMaximumSize(dimensionOfComponent);
        c.gridx = x_pos;
        c.gridy = y_pos;
        c.gridwidth = width;
        c.gridheight = height;
    }

    /**
     * Set the font to bold and italic for a component.
     * 
     * @param comp
     */
    private void setBoldAndItalic(Component comp) {
        Font boldFont = new Font(comp.getFont().getName(), Font.BOLD + Font.ITALIC, comp.getFont().getSize());
        comp.setFont(boldFont);
    }

    /**
     * Set the font to plain (normal) for a component.
     * 
     * @param comp
     */
    private void setPlain(Component comp) {
        Font boldFont = new Font(comp.getFont().getName(), Font.PLAIN, comp.getFont().getSize());
        comp.setFont(boldFont);
    }

    /**
     * If the boolean value is true, creates the border of the component. Otherwise sets an empty border.
     * 
     * @param component
     *            the component whose border will be affected
     * @param isVisible
     *            the border is visible (true) or not (false)
     */
    public void setBorderVisible(Component component, boolean isVisible) {
        if (isVisible) {

            // create border
            Border loweredEtchedBorder = BorderFactory.createEtchedBorder(EtchedBorder.LOWERED);
            Border marginBorder = new EmptyBorder(5, 5, 5, 5);
            if (component instanceof JTextArea) {
                ((JTextArea) component).setBorder(new CompoundBorder(loweredEtchedBorder, marginBorder));
                ;
            } else if (component instanceof JLabel) {
                ((JLabel) component).setBorder(new CompoundBorder(loweredEtchedBorder, marginBorder));
            }
        } else {

            // remove border (set empty border)
            if (component instanceof JTextArea) {
                ((JTextArea) component).setBorder(javax.swing.BorderFactory.createEmptyBorder());
            } else if (component instanceof JLabel) {
                ((JLabel) component).setBorder(javax.swing.BorderFactory.createEmptyBorder());
            }
        }
    }
}
