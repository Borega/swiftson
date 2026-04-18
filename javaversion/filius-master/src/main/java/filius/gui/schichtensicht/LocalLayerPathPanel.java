package filius.gui.schichtensicht;

import java.awt.BorderLayout;
import java.awt.Color;
import java.awt.Component;
import java.awt.Dimension;
import java.util.HashSet;
import java.util.NoSuchElementException;
import java.util.Set;
import javax.swing.JFrame;
import javax.swing.JPanel;
import javax.swing.JSplitPane;
import filius.gui.nachrichtensicht.MessageDetailsTable;
import filius.hardware.knoten.Gateway;
import filius.hardware.knoten.Host;
import filius.hardware.knoten.InternetKnoten;
import filius.hardware.knoten.Knoten;
import filius.hardware.knoten.Vermittlungsrechner;
import filius.rahmenprogramm.nachrichten.Lauscher;
import filius.software.system.SystemSoftware;

/**
 * This class is used to visualise the path of a layer 2 packet (in Filius: IP or ARP packet) through the TCP/IP layers
 * on the selected node (host or router). The idea was taken from the following website and with permission of the
 * creator: https://oinf.ch/interactive/tcp-ip-visualisierung/
 * 
 * @author Christoph Irniger
 */
public class LocalLayerPathPanel extends JPanel {
    private final Knoten NODE;

    private final String INTERFACE_ID;

    /** frame number which was selected by mouse click, starts with 1 */
    private final int FRAME_NUMBER;

    /**
     * Corresponding global layer path object, if it exists. If null, we are in the local layer path view.
     */
    private final GlobalLayerPath globalLayerPath;

    /** if the node sent the frame, otherwise the node received the frame */
    private final boolean SENT;
    /** if the node forwarded an IP or ICMP packet */
    private final boolean FORWARDED;

    private final JSplitPane SPLIT_PANE;
    private static final int DEFAULT_DIVIDER_LOCATION = 475;

    // graphical message details tables
    private MessageDetailsTable tableSent;
    private MessageDetailsTable tableReceived;

    // info about the corresponding frame
    private final String CORR_INTERFACE_ID;
    private final Integer CORR_FRAME_NUMBER;

    /**
     * maximum layer inside the frame (1 = link, 2 = internet, 3 = transport, 4 = application)
     */
    private final int MAX_LAYER_INSIDE_FRAME;
    /**
     * maximum layer on which the node operates (1 = link, 2 = internet, 3 = transport, 4 = application)
     */
    private final int MAX_LAYER_OF_OPERATION;

    /**
     * current number of hidden layers (0 = none, 1 = Link, 2 = Link & Internet, 3 = Link & Internet & Transport)
     */
    private int hiddenLayers;

    private static final Color BACKGROUND_COLOR = Color.WHITE;

    /**
     * determines if this node should be highlighted as the main node (default is false)
     */
    private boolean isMainNode;

    public LocalLayerPathPanel(JFrame owner, String interfaceId, SystemSoftware systemSoftware, int selectedFrameNumber,
            GlobalLayerPath globalLayerPath, boolean isMainNode) {
        super();

        // inherit instance variables from super container (localPathDialog)
        NODE = systemSoftware.getKnoten();
        this.INTERFACE_ID = interfaceId;
        this.FRAME_NUMBER = selectedFrameNumber;
        this.globalLayerPath = globalLayerPath;
        this.isMainNode = isMainNode;
        MAX_LAYER_OF_OPERATION = ((InternetKnoten) getKnoten()).getMaxLayerOfOperation();

        // determine if frame was sent or received
        SENT = isFrameSent(interfaceId, selectedFrameNumber);

        // Depending on wheter the message was sent or received, create the primary
        // message details table (first visible)
        createPrimaryMessageDetailsTable();

        // determine if the packet (inside the frame) was forwarded
        Object[] corrFrameData = Lauscher.getLauscher().getCorrespondingFrame(this.INTERFACE_ID, this.FRAME_NUMBER,
                (InternetKnoten) this.NODE);
        CORR_INTERFACE_ID = (String) corrFrameData[0];
        CORR_FRAME_NUMBER = (Integer) corrFrameData[1];
        FORWARDED = ((NODE instanceof Vermittlungsrechner || NODE instanceof Gateway)
                && (CORR_INTERFACE_ID != null && CORR_FRAME_NUMBER != null));

        // If the message was forwarded, create the secondary message details table
        // (only visible if switched to other interface by using the forth or back
        // button)
        createSecondaryMessageDetailsTable();

        // initialise tables for message details
        if (SENT) {
            MAX_LAYER_INSIDE_FRAME = tableSent.getMaxLayerInsideFrame();
            tableSent.setLayersInvisible();
            if (FORWARDED) {
                tableReceived.setLayersInvisible();
            }
        } else {
            MAX_LAYER_INSIDE_FRAME = tableReceived.getMaxLayerInsideFrame();
            tableReceived.setLayersInvisible();
        }

        // SplitPane (for visualisation in upper and message details in lower part)
        SPLIT_PANE = new JSplitPane();
        SPLIT_PANE.setOrientation(JSplitPane.VERTICAL_SPLIT);
        SPLIT_PANE.setDividerLocation(DEFAULT_DIVIDER_LOCATION);
        // prevent the SplitPane to get user input (mainly to lock the divider)
        SPLIT_PANE.setEnabled(false);

        setFirstMessageDetails();

        // layout manager for this panel
        setLayout(new BorderLayout(10, 10));

        // add splitPane
        add(SPLIT_PANE, BorderLayout.CENTER);

        // set visualisation on top half of the SplitPane
        SPLIT_PANE.setTopComponent(new LocalLayerPathVisualisation(this, globalLayerPath));
    }

    public Knoten getKnoten() {
        return NODE;
    }

    public String getInterfaceId() {
        return INTERFACE_ID;
    }

    public int getMaxLayerInsideFrame() {
        return MAX_LAYER_INSIDE_FRAME;
    }

    public int getMaxLayerOfOperation() {
        return MAX_LAYER_OF_OPERATION;
    }

    public String getCorrInterfaceId() {
        return CORR_INTERFACE_ID;
    }

    public boolean isSent() {
        return SENT;
    }

    public boolean isForwarded() {
        return FORWARDED;
    }

    public int getDefaultDividerLocation() {
        return DEFAULT_DIVIDER_LOCATION;
    }

    public void setDividerLocation(int dividerLocation) {
        SPLIT_PANE.setDividerLocation(dividerLocation);
    }

    public int getDividerLocation() {
        return SPLIT_PANE.getDividerLocation();
    }

    public static Color getBackgroundColor() {
        return BACKGROUND_COLOR;
    }

    public boolean isMainNode() {
        return isMainNode;
    }

    public void setAsMainNode(boolean isMainNode) {
        this.isMainNode = isMainNode;
    }

    public Dimension getSizeOfMessageDetailsTable() {
        return MessageDetailsTable.getSizeOfMessageDetailsTable();
    }

    /**
     * Checks if the selected frame was sent or received (= not sent).
     * 
     * @return true if sent, false if received
     */
    public static boolean isFrameSent(String interfaceId, int selectedFrameNumber) {
        return interfaceId
                .equals(Lauscher.getLauscher().getFrame(interfaceId, selectedFrameNumber).getQuellMacAdresse());
    }

    /**
     * Creates the primary message details table which is seen right after opening the local view.
     * 
     * @return maximum layer that appears inside the frame
     */
    private void createPrimaryMessageDetailsTable() {
        if (SENT) {
            tableSent = new MessageDetailsTable(INTERFACE_ID, FRAME_NUMBER, BACKGROUND_COLOR);
        } else {
            tableReceived = new MessageDetailsTable(INTERFACE_ID, FRAME_NUMBER, BACKGROUND_COLOR);
        }
    }

    /**
     * Only has an effect if the node is a router (or home router). If {@code forwarded} is true, creates the secondary
     * message details table for the other involved interface on the node.
     */
    private void createSecondaryMessageDetailsTable() {
        if (FORWARDED) {
            if (SENT) {
                tableReceived = new MessageDetailsTable(CORR_INTERFACE_ID, CORR_FRAME_NUMBER, BACKGROUND_COLOR);
            } else {
                tableSent = new MessageDetailsTable(CORR_INTERFACE_ID, CORR_FRAME_NUMBER, BACKGROUND_COLOR);
            }
        }
    }

    /**
     * Determines which message details ({@code messageDetailsSent} or {@code messageDetailsReceived}) are shown first
     * directly after opening the window of the local path for the first time and hides and greys out layers depending
     * on the parameters.
     */
    private void setFirstMessageDetails() {
        // for the sender of a message
        if (SENT) {
            SPLIT_PANE.setBottomComponent(tableSent);
            if (NODE instanceof Host) {
                // if in local view or if in global view and active border does not start at end
                // hide all layers except the maximum layer inside the frame (else show all
                // layers)
                if (globalLayerPath == null || !globalLayerPath.isActiveBorderOfNextPanelAtEnd()) {
                    for (int i = 1; i < MAX_LAYER_INSIDE_FRAME; i++) {
                        hideLayerData(i, tableSent);
                    }
                    hiddenLayers = MAX_LAYER_INSIDE_FRAME - 1;
                } else {
                    hiddenLayers = 0;
                }
            } else if (NODE instanceof Vermittlungsrechner || NODE instanceof Gateway) {
                hideLayerData(1, tableSent);
                hiddenLayers = 1;
                if (FORWARDED) {
                    hideLayerData(1, tableReceived);
                }
            }
        }
        // for the receiver of a message
        else {
            if (globalLayerPath != null && globalLayerPath.isActiveBorderOfNextPanelAtEnd()) {
                SPLIT_PANE.setBottomComponent(tableSent);
            } else {
                SPLIT_PANE.setBottomComponent(tableReceived);
            }
        }
        // update greyed out cells (cells invisible to the layer)
        if (SENT) {
            updateGreyedOutCells(tableSent);
            // if the IP packet was forwarded, also update the other table, since it could
            // be needed
            if (FORWARDED) {
                updateGreyedOutCells(tableReceived);
            }
        } else {
            updateGreyedOutCells(tableReceived);
            if (FORWARDED) {
                updateGreyedOutCells(tableSent);
            }
        }
    }

    /**
     * Decides if the message details for the sent or the received message should be displayed.
     * 
     * @param senderSideIsActive
     *            If true, the visualisation is on the sender side, otherwise on the receiver side.
     * @param senderSideWasActive
     *            If true, the visualisation was on the sender side in the last step.
     */
    public void updateMessageDetailsDisplay(boolean senderSideIsActive, boolean senderSideWasActive) {
        if (senderSideIsActive != senderSideWasActive) {
            if (senderSideIsActive) {
                // save old divider location
                int currentDividerLocation = SPLIT_PANE.getDividerLocation();
                // set new table
                SPLIT_PANE.setBottomComponent(tableSent);
                // set old divider location
                SPLIT_PANE.setDividerLocation(currentDividerLocation);
            } else {
                // save old divider location
                int currentDividerLocation = SPLIT_PANE.getDividerLocation();
                // set new table
                SPLIT_PANE.setBottomComponent(tableReceived);
                // set old divider location
                SPLIT_PANE.setDividerLocation(currentDividerLocation);
            }
        }
    }

    /**
     * Hide data of the next higher layer in the message details. Hideable layers are 1 = link, 2 = internet, 3 =
     * transport.
     */
    public void hideNextHigherLayer() {
        if (hiddenLayers <= 2 && hiddenLayers >= 0) {
            hiddenLayers++;
            if (SENT) {
                updateGreyedOutCells(tableSent);
                hideLayerData(hiddenLayers, tableSent);
                if (FORWARDED) {
                    updateGreyedOutCells(tableReceived);
                    hideLayerData(hiddenLayers, tableReceived);
                }
            } else {
                updateGreyedOutCells(tableReceived);
                hideLayerData(hiddenLayers, tableReceived);
                if (FORWARDED) {
                    updateGreyedOutCells(tableSent);
                    hideLayerData(hiddenLayers, tableSent);
                }
            }
        }
    }

    /**
     * Show data of the next lower layer in the message details. Hideable layers are 1 = link, 2 = internet, 3 =
     * transport.
     */
    public void showNextLowerLayer() {
        if (hiddenLayers <= 3 && hiddenLayers >= 1) {
            hiddenLayers--;
            if (SENT) {
                updateGreyedOutCells(tableSent);
                showLayerData(hiddenLayers + 1, tableSent);
                if (FORWARDED) {
                    updateGreyedOutCells(tableReceived);
                    showLayerData(hiddenLayers + 1, tableReceived);
                }
            } else {
                updateGreyedOutCells(tableReceived);
                showLayerData(hiddenLayers + 1, tableReceived);
                if (FORWARDED) {
                    updateGreyedOutCells(tableSent);
                    showLayerData(hiddenLayers + 1, tableSent);
                }
            }
        }
    }

    /**
     * Hide data of a layer in the message details. 1 = link, 2 = internet, 3 = transport.
     * 
     * @param layerNumber
     *            number for layer
     * @param table
     *            table in which layer data should be hidden
     * @throws NoSuchElementException
     */
    private void hideLayerData(int layerNumber, MessageDetailsTable table) throws NoSuchElementException {
        if (layerNumber > 3 || layerNumber < 1) {
            throw new NoSuchElementException("layerNumber has to be an integer from 1 to 3.");
        } else {

            // determine columns to hide
            Set<Integer> columns = new HashSet<>();
            int firstColumn = (layerNumber - 1) * 2;
            columns.add(firstColumn);
            columns.add(firstColumn + 1);

            // hide columns
            for (Component component : table.getComponents()) {
                if (columns.contains(table.getGridBagLayout().getConstraints(component).gridx)
                        && table.getGridBagLayout().getConstraints(component).gridy > 1) {

                    // set foreground and background to main background (such that the component
                    // gets invisible)
                    component.setBackground(table.getBackground());
                    component.setForeground(table.getBackground());

                    // remove border
                    table.setBorderVisible(component, false);
                }
            }
        }
    }

    /**
     * Show data of a layer in the message details. 1 = link, 2 = internet, 3 = transport.
     * 
     * @param layerNumber
     *            number for layer
     * @param table
     *            in which layer data should be shown
     * @throws NoSuchElementException
     */
    private void showLayerData(int layerNumber, MessageDetailsTable table) throws NoSuchElementException {
        if (layerNumber > 3 || layerNumber < 1) {
            throw new NoSuchElementException("layerNumber has to be an integer from 1 to 3.");
        } else {

            // determine columns to show
            Set<Integer> columns = new HashSet<>();
            int firstColumn = (layerNumber - 1) * 2;
            columns.add(firstColumn);
            columns.add(firstColumn + 1);

            // show columns
            for (Component component : table.getComponents()) {
                if (columns.contains(table.getGridBagLayout().getConstraints(component).gridx)) {
                    int gridy = table.getGridBagLayout().getConstraints(component).gridy;
                    if (gridy > 1) {

                        // set colors
                        component.setForeground(MessageDetailsTable.getLayerColorVar("foregroundColor", layerNumber));
                        if (gridy == 0) {
                            component.setBackground(
                                    MessageDetailsTable.getLayerColorVar("backgroundColorFine", layerNumber));
                        } else {
                            component.setBackground(
                                    MessageDetailsTable.getLayerColorVar("backgroundColor", layerNumber));

                            // create border
                            table.setBorderVisible(component, true);
                        }
                    }
                }
            }
        }
    }

    /**
     * Set all cells which represent content of the message (i.e. the ones with y coordinate greater than 1) greyed out
     * according to {@code hiddenlayers} and {@code MAX_LAYER_INSIDE_FRAME}.
     * 
     * @param table
     *            the table whose cells should be updated
     */
    private void updateGreyedOutCells(MessageDetailsTable table) {
        // determine columns to be greyed out
        Set<Integer> columns = new HashSet<>();
        for (int columnNo = (hiddenLayers + 1) * 2; columnNo <= 6; columnNo++) {
            columns.add(columnNo);
        }

        // grey out those components
        for (Component component : table.getComponents()) {
            int xCoord = table.getGridBagLayout().getConstraints(component).gridx;
            int yCoord = table.getGridBagLayout().getConstraints(component).gridy;
            if (yCoord >= 2) {
                if (columns.contains(xCoord)) {
                    // if content is in the internet layer
                    if (xCoord >= 2 && xCoord <= 3) {
                        setComponentGreyedOut(component, 2);
                    }
                    // if content is in the transport layer
                    else if (xCoord >= 4 && xCoord <= 5) {
                        setComponentGreyedOut(component, 3);
                    }
                    // if content is in the application layer
                    else if (xCoord == 6) {
                        setComponentGreyedOut(component, 4);
                    }
                }
                // if it is not the last column
                else if (xCoord != 7) {
                    // if content is in the internet layer
                    if (xCoord >= 2 && xCoord <= 3) {
                        resetComponentFromGreyedOut(component, 2);
                    }
                    // if content is in the transport layer
                    else if (xCoord >= 4 && xCoord <= 5) {
                        resetComponentFromGreyedOut(component, 3);
                    }
                    // if content is in the application layer
                    else if (xCoord == 6) {
                        resetComponentFromGreyedOut(component, 4);
                    }
                }
            }
        }
    }

    /**
     * Set a components' foreground color (font color) to "greyed out" and the background color to the corresponding
     * background color in ultra fine variant.
     * 
     * @param comp
     * @param layerNumber
     */
    private void setComponentGreyedOut(Component component, int layerNumber) {
        component.setForeground(MessageDetailsTable.getLayerColorVar("foregroundColorGreyedOut", layerNumber));
        component.setBackground(MessageDetailsTable.getLayerColorVar("backgroundColorUltraFine", layerNumber));
    }

    /**
     * Reset a components' foreground color (font color) to black and the background color to the corresponding
     * background color.
     * 
     * @param comp
     * @param layerNumber
     */
    private void resetComponentFromGreyedOut(Component component, int layerNumber) {
        // only reset if not hidden
        if (hiddenLayers < layerNumber) {
            component.setForeground(Color.BLACK);
            component.setBackground(MessageDetailsTable.getLayerColorVar("backgroundColor", layerNumber));
        }
    }
}