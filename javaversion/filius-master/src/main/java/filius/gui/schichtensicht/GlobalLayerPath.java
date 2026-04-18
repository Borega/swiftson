package filius.gui.schichtensicht;

import java.util.ArrayList;

import javax.swing.JFrame;
import javax.swing.JPanel;

import filius.hardware.knoten.InternetKnoten;
import filius.hardware.knoten.Knoten;
import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.nachrichten.Lauscher;
import filius.software.netzzugangsschicht.Ethernet;
import filius.software.netzzugangsschicht.EthernetFrame;
import filius.software.system.SystemSoftware;
import filius.software.vermittlungsschicht.ArpPaket;
import filius.software.vermittlungsschicht.IpPaket;

/**
 * This class is used to visualise the end-to-end path of of an IP packet layer 2 packet (in Filius: IP or ARP packet)
 * through the TCP/IP layers of all the nodes it went through. The idea was taken from the following website and with
 * permission of the creator: https://oinf.ch/interactive/tcp-ip-visualisierung/
 * 
 * I want to emphasize that this view does not correspond to reality. In packet-switching net- works like the internet a
 * single node in general cannnot possible track the end-to-end path of a message. This follows immediately from the
 * properties of the packet-switching network model.
 * 
 * The purpose of this view is to help learners understand the principle of the layers of the TCP/IP model.
 * 
 * @author Christoph Irniger
 */

public class GlobalLayerPath extends JPanel implements I18n {
    private static final Lauscher LAUSCHER = Lauscher.getLauscher();
    private static final int MAX_TTL = 64;

    private final JFrame OWNER;
    private final String MAIN_INTERFACE_ID;
    private final Knoten MAIN_NODE;
    private final int MAIN_FRAME_NUMBER;
    private final EthernetFrame MAIN_FRAME;

    /** local path view of the selected node */
    private final LayerPathDialog MAIN_DIALOG;
    private final LocalLayerPathPanel MAIN_LOCAL_PANEL;

    private int currentLocalPanelPathIndex = 0;
    private int currentLocalPanelParametersPathIndex = 0;

    /** if the active border of the next local panel should be at the end */
    private boolean activeBorderOfNextPanelAtEnd;

    /**
     * Path of a packet represented as list of ethernet frames encapsulating this packet in chronological order of
     * creation.
     */
    ArrayList<EthernetFrame> framePath = new ArrayList<EthernetFrame>();

    /**
     * List of {@code LocalLayerPathPanel} objects corresponding to the nodes involved in the path of a packet in
     * chronological order (i.e. sender node comes first, then all the routers and at last the receiver node).
     * {@code LocalLayerPathPanel} objects will be created only when they are needed and then added to the list.
     */
    ArrayList<LocalLayerPathPanel> localPanelPath = new ArrayList<LocalLayerPathPanel>();
    /**
     * List of the parameters which are needed to create an object of {@code LocalLayerPathPanel}. This list will get
     * filled immediately after opening the global view.
     */
    ArrayList<Object[]> localPanelParametersPath = new ArrayList<Object[]>();
    /**
     * The parameters needed to create the main local panel.
     */
    Object[] MAIN_LOCAL_PANEL_PARAMETERS;

    public GlobalLayerPath(JFrame owner, String interfaceId, SystemSoftware systemSoftware, int frameNumber) {
        this.OWNER = owner;
        MAIN_NODE = (InternetKnoten) systemSoftware.getKnoten();
        MAIN_LOCAL_PANEL_PARAMETERS = new Object[] { interfaceId, systemSoftware, frameNumber };
        MAIN_INTERFACE_ID = interfaceId;
        MAIN_FRAME_NUMBER = frameNumber;
        MAIN_FRAME = LAUSCHER.getFrame(MAIN_INTERFACE_ID, MAIN_FRAME_NUMBER);

        MAIN_DIALOG = new LayerPathDialog(owner, interfaceId, systemSoftware, frameNumber, this, true);
        MAIN_LOCAL_PANEL = MAIN_DIALOG.getLocalLayerPathPanel();
        MAIN_LOCAL_PANEL.setAsMainNode(true);

        // overwrite title to "Globaler Weg durch die Schichten"
        MAIN_DIALOG.setTitle(messages.getString("schichten_globaler_weg_msg1"));

        fillFramePath();
        localPanelPath.add(MAIN_LOCAL_PANEL);
        fillLocalPanelParametersPath();

        // nächste Zeile wird überflüssig, da dort sowieso nur MAIN_LOCA_PANEL drin ist
        currentLocalPanelParametersPathIndex = localPanelParametersPath.indexOf(MAIN_LOCAL_PANEL_PARAMETERS);
        MAIN_DIALOG.setVisible(true);
    }

    public boolean isActiveBorderOfNextPanelAtEnd() {
        return activeBorderOfNextPanelAtEnd;
    }

    /**
     * Fills the frame path list with all the frames involved in delivering the IP packet.
     */
    private void fillFramePath() {
        // if frame is an ARP packet or was received via ethernet broadcast (possible
        // with ARP and DHCP)
        if (MAIN_FRAME.getDaten() instanceof ArpPaket
                || (MAIN_FRAME.getZielMacAdresse().equals(Ethernet.ETHERNET_BROADCAST)
                        && !MAIN_FRAME.getQuellMacAdresse().equals(MAIN_INTERFACE_ID))) {
            addToFramePath(MAIN_FRAME);
        } else if (MAIN_FRAME.getDaten() instanceof IpPaket) {
            for (int ttl = MAX_TTL; ttl > 0; ttl--) {
                EthernetFrame frame = LAUSCHER.getFrameWithSameContentAndSpecificTTL(MAIN_FRAME, ttl);
                if (frame != null) {
                    addToFramePath(frame);
                } else {
                    break;
                }
            }
        }
    }

    /**
     * Adds the frame to the frame path.
     * 
     * @param frame
     *            frame to be added to {@code framePath}
     */
    private void addToFramePath(EthernetFrame frame) {
        // if frame is exactly the same (incl. TTL) as the main frame
        if (frame.sameContent(MAIN_FRAME)) {
            framePath.add(MAIN_FRAME);
        } else {
            framePath.add(frame);
        }
    }

    /**
     * Fills the local panel parameters array path list with all the parameter arrays for the local panels involved in
     * delivering the IP packet.
     */
    private void fillLocalPanelParametersPath() {
        // frame was received via ethernet broadcast
        if (MAIN_FRAME.getZielMacAdresse().equals(Ethernet.ETHERNET_BROADCAST)
                && !MAIN_FRAME.getQuellMacAdresse().equals(MAIN_INTERFACE_ID)) {
            // add sender
            String interfaceId = MAIN_FRAME.getQuellMacAdresse();
            SystemSoftware systemSoftware = LAUSCHER.getSystemSoftwareByID(interfaceId);
            int frameNumber = LAUSCHER.getFrameNumber(interfaceId, MAIN_FRAME);
            addToLocalPanelPath(interfaceId, systemSoftware, frameNumber);

            // add receiver
            interfaceId = MAIN_INTERFACE_ID;
            systemSoftware = LAUSCHER.getSystemSoftwareByID(interfaceId);
            frameNumber = LAUSCHER.getFrameNumber(interfaceId, MAIN_FRAME);
            addToLocalPanelPath(interfaceId, systemSoftware, frameNumber);
        } else {
            EthernetFrame firstFrame = framePath.get(0);

            // add original sender
            String interfaceId = firstFrame.getQuellMacAdresse();
            SystemSoftware systemSoftware = LAUSCHER.getSystemSoftwareByID(interfaceId);
            int frameNumber = LAUSCHER.getFrameNumber(interfaceId, firstFrame);
            addToLocalPanelPath(interfaceId, systemSoftware, frameNumber);

            // add routers (corresponding to the destination MAC of the frame in the list,
            // starting with the first) and the final receiver
            for (EthernetFrame frame : framePath) {
                interfaceId = frame.getZielMacAdresse();
                systemSoftware = LAUSCHER.getSystemSoftwareByID(interfaceId);
                frameNumber = LAUSCHER.getFrameNumber(interfaceId, frame);
                addToLocalPanelPath(interfaceId, systemSoftware, frameNumber);
            }
        }
    }

    /**
     * Adds the panel of the local view corresponding to the parameters to the local panels path.
     * 
     * @param interfaceId
     *            ID of the network interface
     * @param systemSoftware
     *            system software running on the node
     * @param frameNumber
     *            number of the frame in the data exchange window (starts with 1)
     */
    private void addToLocalPanelPath(String interfaceId, SystemSoftware systemSoftware, int frameNumber) {
        // if the interface is on the main node and the TTL corresponds to the one of
        // the main frame (depending if the frame was sent or received), add the main
        // panel
        EthernetFrame frame = LAUSCHER.getFrame(interfaceId, frameNumber);
        if ((systemSoftware.getKnoten()).equals(MAIN_NODE)) {
            if (!MAIN_LOCAL_PANEL.isForwarded()) {
                localPanelParametersPath.add(MAIN_LOCAL_PANEL_PARAMETERS);
                return;
            } else {
                if (MAIN_FRAME.getDaten() instanceof IpPaket) {
                    if ((MAIN_LOCAL_PANEL.isSent()
                            && ((IpPaket) MAIN_FRAME.getDaten()).getTtl() == ((IpPaket) frame.getDaten()).getTtl() - 1)
                            || (!MAIN_LOCAL_PANEL.isSent() && ((IpPaket) MAIN_FRAME.getDaten())
                                    .getTtl() == ((IpPaket) frame.getDaten()).getTtl())) {
                        localPanelParametersPath.add(MAIN_LOCAL_PANEL_PARAMETERS);
                        return;
                    }
                }
            }
        }
        // If the main panel is not (yet) contained in the list, the active border of
        // the next panel should be at the end (the latest point in time), since if it
        // shows up, it happened through the "back" button.
        localPanelParametersPath.add(new Object[] { interfaceId, systemSoftware, frameNumber });
    }

    /**
     * Switches to the view in the main dialog window to the next or previous local panel of the local panel path list.
     * 
     * @param switchForward
     *            true, if the view should switch forward to the next local panel, false if it should switch back
     */
    public void switchPanel(Boolean switchForward) {
        LocalLayerPathPanel oldPanel = localPanelPath.get(currentLocalPanelPathIndex);
        LocalLayerPathPanel newPanel;
        oldPanel.setVisible(false);
        MAIN_DIALOG.remove(oldPanel);
        if (switchForward) {
            currentLocalPanelPathIndex++;
            currentLocalPanelParametersPathIndex++;
            // if the old panel ist not the last element
            if (currentLocalPanelPathIndex - 1 < localPanelPath.size() - 1) {
                newPanel = localPanelPath.get(currentLocalPanelPathIndex);
            } else {
                Object[] parameters = localPanelParametersPath.get(currentLocalPanelParametersPathIndex);
                String interfaceId = (String) parameters[0];
                SystemSoftware systemSoftware = (SystemSoftware) parameters[1];
                int frameNumber = (int) parameters[2];
                activeBorderOfNextPanelAtEnd = false;
                newPanel = new LocalLayerPathPanel(OWNER, interfaceId, systemSoftware, frameNumber, this, false);
                localPanelPath.add(newPanel);
            }
        } else {
            currentLocalPanelParametersPathIndex--;
            // if the old panel ist not the first element
            if (currentLocalPanelPathIndex > 0) {
                currentLocalPanelPathIndex--;
                newPanel = localPanelPath.get(currentLocalPanelPathIndex);
                MAIN_DIALOG.add(newPanel);
            } else {
                Object[] parameters = localPanelParametersPath.get(currentLocalPanelParametersPathIndex);
                String interfaceId = (String) parameters[0];
                SystemSoftware systemSoftware = (SystemSoftware) parameters[1];
                int frameNumber = (int) parameters[2];
                activeBorderOfNextPanelAtEnd = true;
                newPanel = new LocalLayerPathPanel(OWNER, interfaceId, systemSoftware, frameNumber, this, false);
                localPanelPath.add(0, newPanel);
            }
        }
        newPanel.setDividerLocation(oldPanel.getDividerLocation());
        MAIN_DIALOG.add(newPanel);
        newPanel.setVisible(true);
    }
}