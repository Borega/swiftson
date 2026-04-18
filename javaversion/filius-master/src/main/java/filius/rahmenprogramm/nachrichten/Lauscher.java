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
package filius.rahmenprogramm.nachrichten;

import java.text.NumberFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collection;
import java.util.GregorianCalendar;
import java.util.HashMap;
import java.util.LinkedList;
import java.util.List;
import java.util.ListIterator;
import java.util.Vector;

import org.apache.commons.lang3.StringUtils;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.hardware.NetzwerkInterface;
import filius.hardware.knoten.InternetKnoten;
import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.Information;
import filius.software.netzzugangsschicht.EthernetFrame;
import filius.software.system.SystemSoftware;
import filius.software.transportschicht.TcpSegment;
import filius.software.transportschicht.UdpSegment;
import filius.software.vermittlungsschicht.ArpPaket;
import filius.software.vermittlungsschicht.IcmpPaket;
import filius.software.vermittlungsschicht.IpPaket;

public class Lauscher implements I18n {
    private static Logger LOG = LoggerFactory.getLogger(Lauscher.class);

    public static final String ETHERNET = "", ARP = "ARP", IP = "IP", ICMP = "ICMP", TCP = "TCP", UDP = "UDP";

    public static final String HTTP = "HTTP", SMTP = "SMTP", POP = "POP3", DNS = "DNS", DHCP = "DHCP";

    public static final String[] SPALTEN = { messages.getString("rp_lauscher_msg1"),
            messages.getString("rp_lauscher_msg2"), messages.getString("rp_lauscher_msg3"),
            messages.getString("rp_lauscher_msg4"), messages.getString("rp_lauscher_msg5"),
            messages.getString("rp_lauscher_msg6"), messages.getString("rp_lauscher_msg7") };

    public static final String[] PROTOKOLL_SCHICHTEN = { messages.getString("rp_lauscher_msg8"),
            messages.getString("rp_lauscher_msg9"), messages.getString("rp_lauscher_msg10"),
            messages.getString("rp_lauscher_msg11") };

    public static final String DROPPED = "dropped packets";

    private NumberFormat numberFormatter = NumberFormat.getInstance(Information.getInformation().getLocaleOrDefault());

    /** Singleton */
    private static Lauscher lauscher = null;

    private HashMap<String, LinkedList<LauscherBeobachter>> beobachter = new HashMap<String, LinkedList<LauscherBeobachter>>();

    private HashMap<String, LinkedList<Object[]>> datenEinheiten = new HashMap<String, LinkedList<Object[]>>();
    private List<Object[]> droppedDataUnits = new LinkedList<>();

    private HashMap<String, NetzwerkInterface> InterfaceById = new HashMap<String, NetzwerkInterface>();
    private HashMap<String, SystemSoftware> SystemSoftwareById = new HashMap<String, SystemSoftware>();

    private Lauscher() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", constr: Lauscher()");
        reset();
    }

    public void reset() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", reset()");
        datenEinheiten.clear();
        droppedDataUnits.clear();
        this.benachrichtigeBeobachter(null);
    }

    public Collection<String> getInterfaceIDs() {
        return datenEinheiten.keySet();
    }

    public static Lauscher getLauscher() {
        if (lauscher == null) {
            lauscher = new Lauscher();
        }
        return lauscher;
    }

    public NetzwerkInterface getInterfaceByID(String interfaceId) {
        return InterfaceById.get(interfaceId);
    }

    public SystemSoftware getSystemSoftwareByID(String interfaceId) {
        return SystemSoftwareById.get(interfaceId);
    }

    public void removeIdentifier(String identifier) {
        datenEinheiten.remove(identifier);
        beobachter.remove(identifier);
    }

    public void addBeobachter(String id, LauscherBeobachter newObserver) {
        LOG.trace(
                "INVOKED (" + this.hashCode() + ") " + getClass() + ", addBeobachter(" + id + "," + newObserver + ")");
        LinkedList<LauscherBeobachter> liste;

        liste = this.beobachter.get(id);
        if (liste == null) {
            liste = new LinkedList<LauscherBeobachter>();
            this.beobachter.put(id, liste);
        }
        liste.add(newObserver);
    }

    private void benachrichtigeBeobachter(String id) {
        LinkedList<LauscherBeobachter> liste = new LinkedList<LauscherBeobachter>();
        if (id == null) {
            for (LinkedList<LauscherBeobachter> beobachterListe : beobachter.values()) {
                liste.addAll(beobachterListe);
            }
        } else if (null == beobachter.get(id)) {
            LOG.trace("no observer for {}", id);
        } else {
            liste.addAll(beobachter.get(id));
        }
        for (LauscherBeobachter beobachter : liste) {
            beobachter.update();
        }
    }

    /**
     * Hinzufuegen von einem EthernetFrame zu den Daten
     * 
     * @param networkInterface
     * @param systemSoftware
     * @param frame
     */
    public void addDatenEinheit(NetzwerkInterface networkInterface, SystemSoftware systemSoftware,
            EthernetFrame frame) {
        String interfaceId = networkInterface.getMac();
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", addDatenEinheit(" + interfaceId + "," + frame
                + ")");
        if (!frame.isReadByLauscherForMac(interfaceId)) {
            Object[] frameMitZeitstempel = frameWithTimestamp(frame);

            LinkedList<Object[]> liste = (LinkedList<Object[]>) datenEinheiten.get(interfaceId);
            if (liste == null) {
                liste = new LinkedList<Object[]>();
                datenEinheiten.put(interfaceId, liste);
            }
            synchronized (liste) {
                liste.addLast(frameMitZeitstempel);
            }
            frame.setReadByLauscherForMac(interfaceId);
            benachrichtigeBeobachter(interfaceId);
        }
        storeInterfaceById(interfaceId, networkInterface);
        storeSystemSoftwareById(interfaceId, systemSoftware);
    }

    public void addDroppedDataUnit(EthernetFrame frame) {
        Object[] frameMitZeitstempel = frameWithTimestamp(frame);
        droppedDataUnits.add(frameMitZeitstempel);
        benachrichtigeBeobachter(DROPPED);
    }

    protected Object[] frameWithTimestamp(EthernetFrame frame) {
        Object[] frameMitZeitstempel = new Object[2];
        frameMitZeitstempel[0] = Long.valueOf(System.currentTimeMillis());
        frameMitZeitstempel[1] = frame.clone();
        return frameMitZeitstempel;
    }

    public Object[][] getDaten(String interfaceId, boolean inheritAddress, int offset) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", getDaten(" + interfaceId + ")");
        Vector<Object[]> vector;
        Object[][] daten;

        vector = datenVorbereiten(interfaceId, inheritAddress, offset);
        if (vector == null) {
            daten = new Object[0][SPALTEN.length];
            return daten;
        } else {
            daten = new Object[vector.size()][SPALTEN.length];
            for (int i = 0; i < vector.size(); i++) {
                daten[i] = (Object[]) vector.elementAt(i);
            }
            return daten;
        }
    }

    public void print(String interfaceId) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", print(" + interfaceId + ")");
        Object[][] daten;

        daten = getDaten(interfaceId, false, 1);
        for (int i = 0; i < daten.length; i++) {
            for (int j = 0; j < daten[i].length; j++) {
                LOG.debug("\t" + daten[i][j]);
            }
        }
    }

    public int getOffsetByTimestamp(String interfaceId, long offsetTimestamp) {
        LinkedList<Object[]> liste = datenEinheiten.get(interfaceId);
        int offset = 1;
        if (liste != null) {
            synchronized (liste) {
                for (Object[] frameMitZeitstempel : liste) {
                    long timestamp = ((Long) frameMitZeitstempel[0]).longValue();
                    if (timestamp >= offsetTimestamp) {
                        break;
                    }
                    offset++;
                }
            }
        }
        return offset;
    }

    private String formatTimestamp(long timestamp) {
        Calendar zeit = new GregorianCalendar();
        zeit.setTimeInMillis(timestamp);
        String timestampStr = (zeit.get(Calendar.HOUR_OF_DAY) < 10 ? "0" + zeit.get(Calendar.HOUR_OF_DAY)
                : zeit.get(Calendar.HOUR_OF_DAY)) + ":"
                + (zeit.get(Calendar.MINUTE) < 10 ? "0" + zeit.get(Calendar.MINUTE) : zeit.get(Calendar.MINUTE)) + ":"
                + (zeit.get(Calendar.SECOND) < 10 ? "0" + zeit.get(Calendar.SECOND) : zeit.get(Calendar.SECOND)) + "."
                + (zeit.get(Calendar.MILLISECOND) < 10 ? "00" + zeit.get(Calendar.MILLISECOND)
                        : (zeit.get(Calendar.MILLISECOND) < 100 ? "0" + zeit.get(Calendar.MILLISECOND)
                                : zeit.get(Calendar.MILLISECOND)));
        return timestampStr;
    }

    /**
     * 
     * @param interfaceId
     * @param inheritAddress
     * @param offset
     *            starts with 1
     * @return
     */
    private Vector<Object[]> datenVorbereiten(String interfaceId, boolean inheritAddress, int offset) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + ", datenVorbereiten(" + interfaceId + ")");
        Vector<Object[]> daten;
        LinkedList<Object[]> liste;
        Object[] frameMitZeitstempel, neuerEintrag;
        ListIterator<Object[]> it;
        EthernetFrame frame;
        IpPaket ipPaket;
        IcmpPaket icmpPaket;
        ArpPaket arpPaket;
        TcpSegment tcpSeg = null;
        UdpSegment udpSeg = null;

        liste = datenEinheiten.get(interfaceId);
        if (liste == null) {
            return null;
        } else {
            daten = new Vector<Object[]>();

            synchronized (liste) {
                it = liste.listIterator();
                for (int i = 1; it.hasNext(); i++) {
                    frameMitZeitstempel = (Object[]) it.next();
                    if (i < offset) {
                        continue;
                    }
                    neuerEintrag = new Object[SPALTEN.length];
                    neuerEintrag[0] = "" + i;

                    String timestampStr = formatTimestamp((Long) frameMitZeitstempel[0]);

                    neuerEintrag[1] = timestampStr;
                    frame = (EthernetFrame) frameMitZeitstempel[1];
                    neuerEintrag[2] = frame.getQuellMacAdresse();
                    neuerEintrag[3] = frame.getZielMacAdresse();
                    neuerEintrag[4] = ETHERNET;
                    neuerEintrag[5] = PROTOKOLL_SCHICHTEN[0];
                    neuerEintrag[6] = frame.getTyp();

                    daten.addElement(neuerEintrag);

                    neuerEintrag = new Object[SPALTEN.length];
                    neuerEintrag[0] = "" + i;

                    neuerEintrag[1] = timestampStr;

                    if (frame.getTyp().equals(EthernetFrame.IP) && !(frame.getDaten() instanceof IcmpPaket)) {
                        ipPaket = (IpPaket) frame.getDaten();
                        neuerEintrag[2] = ipPaket.getSender();
                        neuerEintrag[3] = ipPaket.getEmpfaenger();
                        neuerEintrag[4] = IP;
                        neuerEintrag[5] = PROTOKOLL_SCHICHTEN[1];
                        neuerEintrag[6] = messages.getString("rp_lauscher_msg12") + ": " + ipPaket.getProtocol()
                                + ", TTL: " + ipPaket.getTtl();
                        daten.addElement(neuerEintrag);

                        neuerEintrag = new Object[SPALTEN.length];
                        neuerEintrag[0] = "" + i;

                        neuerEintrag[1] = timestampStr;

                        String source = null;
                        String dest = null;

                        if (ipPaket.getProtocol() == IpPaket.TCP) {
                            tcpSeg = (TcpSegment) ipPaket.getSegment();

                            if (inheritAddress) {
                                source = ipPaket.getSender() + ":" + tcpSeg.getQuellPort();
                                neuerEintrag[2] = source;
                                dest = ipPaket.getEmpfaenger() + ":" + tcpSeg.getZielPort();
                                neuerEintrag[3] = dest;
                            } else {
                                neuerEintrag[2] = tcpSeg.getQuellPort();
                                neuerEintrag[3] = tcpSeg.getZielPort();
                            }
                            neuerEintrag[4] = TCP;
                            neuerEintrag[5] = PROTOKOLL_SCHICHTEN[2];
                            if (tcpSeg.isSyn()) {
                                neuerEintrag[6] = "SYN";
                            } else if (tcpSeg.isFin()) {
                                neuerEintrag[6] = "FIN";
                            }
                            neuerEintrag[6] = ((neuerEintrag[6] == null) ? "" : neuerEintrag[6] + ", ") + "SEQ: "
                                    + numberFormatter.format(tcpSeg.getSeqNummer());
                            if (tcpSeg.isAck()) {
                                neuerEintrag[6] = neuerEintrag[6] + ", ACK: "
                                        + numberFormatter.format(tcpSeg.getAckNummer());
                            }
                        } else if (ipPaket.getProtocol() == IpPaket.UDP) {
                            udpSeg = (UdpSegment) ipPaket.getSegment();
                            if (inheritAddress) {
                                source = ipPaket.getSender() + ":" + udpSeg.getQuellPort();
                                neuerEintrag[2] = source;
                                dest = ipPaket.getEmpfaenger() + ":" + udpSeg.getZielPort();
                                neuerEintrag[3] = dest;
                            } else {
                                neuerEintrag[2] = udpSeg.getQuellPort();
                                neuerEintrag[3] = udpSeg.getZielPort();
                            }
                            neuerEintrag[4] = UDP;
                            neuerEintrag[5] = PROTOKOLL_SCHICHTEN[2];
                            neuerEintrag[6] = "";
                        } else {
                            LOG.warn("Protokoll der Transportschicht (" + ipPaket.getProtocol() + ") nicht bekannt.");
                        }
                        daten.addElement(neuerEintrag);

                        neuerEintrag = new Object[SPALTEN.length];
                        neuerEintrag[0] = "" + i;

                        neuerEintrag[1] = timestampStr;
                        neuerEintrag[2] = source;
                        neuerEintrag[3] = dest;
                        neuerEintrag[5] = PROTOKOLL_SCHICHTEN[3];
                        if (ipPaket.getProtocol() == IpPaket.TCP) {
                            neuerEintrag[6] = tcpSeg.getDaten();
                        } else if (ipPaket.getProtocol() == IpPaket.UDP) {
                            neuerEintrag[6] = udpSeg.getDaten();
                        }
                        String payload = (String) neuerEintrag[6];
                        if (payload != null && !payload.trim().equals("")) {
                            neuerEintrag[4] = classifyApplicationLayerProtocol(payload, ipPaket.getProtocol(),
                                    ipPaket.getSegment().getQuellPort(), ipPaket.getSegment().getZielPort());
                            daten.addElement(neuerEintrag);
                        }
                    } else if (frame.getTyp().equals(EthernetFrame.ARP)) {
                        arpPaket = (ArpPaket) frame.getDaten();
                        neuerEintrag[2] = arpPaket.getSenderIP();
                        neuerEintrag[3] = arpPaket.getTargetIP();
                        neuerEintrag[4] = ARP;
                        neuerEintrag[5] = PROTOKOLL_SCHICHTEN[1];
                        if (arpPaket.getOperation() == ArpPaket.REQUEST) {
                            neuerEintrag[6] = messages.getString("rp_lauscher_msg13") + " " + arpPaket.getTargetIP();
                        } else {
                            neuerEintrag[6] = messages.getString("rp_lauscher_msg14") + " " + arpPaket.getSenderMAC();
                        }
                        neuerEintrag[6] += " " + arpPaket.toString();
                        daten.addElement(neuerEintrag);
                    } else if (frame.getTyp().equals(EthernetFrame.IP) && frame.getDaten() instanceof IcmpPaket) {
                        icmpPaket = (IcmpPaket) frame.getDaten();
                        neuerEintrag[2] = icmpPaket.getSender();
                        neuerEintrag[3] = icmpPaket.getEmpfaenger();
                        neuerEintrag[4] = ICMP;
                        neuerEintrag[5] = PROTOKOLL_SCHICHTEN[1];
                        switch (icmpPaket.getIcmpType()) {
                        case 0:
                            neuerEintrag[6] = "ICMP Echo Reply (pong)";
                            break;
                        case 3:
                            switch (icmpPaket.getIcmpCode()) {
                            case 0:
                                neuerEintrag[6] = "ICMP Network Unreachable";
                                break;
                            case 1:
                                neuerEintrag[6] = "ICMP Host Unreachable";
                                break;
                            default:
                                neuerEintrag[6] = "ICMP Destination Unreachable (code " + icmpPaket.getIcmpCode() + ")";
                                break;
                            }
                            break;
                        case 8:
                            neuerEintrag[6] = "ICMP Echo Request (ping)";
                            break;
                        case 11:
                            neuerEintrag[6] = "ICMP Time Exeeded (poof)";
                            break;
                        default:
                            neuerEintrag[6] = "ICMP unknown: " + icmpPaket.getIcmpType() + " / "
                                    + icmpPaket.getIcmpCode();
                            break;
                        }
                        neuerEintrag[6] = neuerEintrag[6] + ", TTL: " + icmpPaket.getTtl() +", Identifier: "+ icmpPaket.getIdentifier() +", Seq.-No.: "
                                + icmpPaket.getSeqNr();
                        if (icmpPaket.getPayload() != null) {
                        	neuerEintrag[6] += ", Payload: " + icmpPaket.getPayload().toString();
                        }

                        daten.addElement(neuerEintrag);
                    }
                }
            }
        }
        return daten;
    }

    private String classifyApplicationLayerProtocol(String payload, int transport, int sourcePort, int destPort) {
        String protocol = "";
        if (StringUtils.contains(payload, "//0x00//") || StringUtils.contains(payload, "//0x01//")
                || StringUtils.contains(payload, "//0x80//") || StringUtils.contains(payload, "//0x81//")
                || StringUtils.contains(payload, "//0x40//")) {
            protocol = "GNT";
        } else if (sourcePort == 110
                && (StringUtils.startsWithIgnoreCase(payload, "+OK")
                        || StringUtils.startsWithIgnoreCase(payload, "-ERR"))
                || destPort == 110 && (StringUtils.startsWithIgnoreCase(payload, "USER ")
                        || StringUtils.startsWithIgnoreCase(payload, "PASS ")
                        || StringUtils.startsWithIgnoreCase(payload, "STAT ")
                        || StringUtils.startsWithIgnoreCase(payload, "LIST ")
                        || StringUtils.startsWithIgnoreCase(payload, "RETR ")
                        || StringUtils.startsWithIgnoreCase(payload, "DELE ")
                        || StringUtils.startsWithIgnoreCase(payload, "NOOP")
                        || StringUtils.startsWithIgnoreCase(payload, "RSET")
                        || StringUtils.startsWithIgnoreCase(payload, "QUIT")
                        || StringUtils.startsWithIgnoreCase(payload, "TOP"))) {
            protocol = "POP3";
        } else if (sourcePort == 25 && (StringUtils.startsWithIgnoreCase(payload, "1")
                || StringUtils.startsWithIgnoreCase(payload, "2") || StringUtils.startsWithIgnoreCase(payload, "3")
                || StringUtils.startsWithIgnoreCase(payload, "4") || StringUtils.startsWithIgnoreCase(payload, "5"))
                || destPort == 25) {
            protocol = "SMTP";
        } else if (StringUtils.contains(payload, "ID=") && StringUtils.contains(payload, "QR=")
                && StringUtils.contains(payload, "RCODE=")) {
            protocol = "DNS";
        } else if (StringUtils.contains(payload, "DHCP")) {
            protocol = "DHCP";
        } else if (sourcePort == 521 && destPort == 520 || sourcePort == 520 && destPort == 521) {
            protocol = "RIP";
        } else if (destPort == 80 && StringUtils.containsIgnoreCase(payload, "http/") || sourcePort == 80) {
            protocol = "HTTP";
        }
        return protocol;
    }

    public String[] getHeader() {
        return Lauscher.SPALTEN;
    }

    public List<String> getDroppedDataUnits() {
        List<String> list = new ArrayList<>();
        for (Object[] droppedDataUnit : droppedDataUnits) {
            list.add(String.format("%s : %s", formatTimestamp((Long) droppedDataUnit[0]), droppedDataUnit[1]));
        }
        return list;
    }

    public void resetDroppedDataUnits() {
        droppedDataUnits.clear();
    }

    /**
     * General: If a frame was forwarded by the node (this means that it is a router), given a received / sent frame,
     * the method finds the sent / received frame with the same encapsuled IP packet on another interface of the node.
     * 
     * Specific: Given an interface ID and the frame number in the data exchange window (Datenaustausch), other
     * interfaces of the node will be searched for a frame which has the same content and a TTL increased by 1 if the
     * frame was sent or a TTL decreased by 1 if the frame was received. <br \> The first entry of the returned array
     * contains the network interface ID {@code interfaceId} and the second entry the number of the frame
     * {@code frameNumber} in the data exchange window. If the two entries are the null pointer each, it means that the
     * layer 2 (IP or ICMP) packet was originally sent or ultimately received by this node, i.e. that there is no
     * corresponding frame.
     * 
     * @param originalInterfaceId
     *            MAC address of the network interface
     * @param originalFrameNumber
     *            number of the frame in the data exchange window (Datenaustausch)
     * @param node
     *            The node whose message details table (Datenaustausch) we are on
     * @return Array of length two. First entry is the interface ID, second entry the frame number in the data exchange
     *         window (starts with 1). If no corresponding frame exists, the two entries are null.
     * @author Christoph Irniger
     */
    public Object[] getCorrespondingFrame(String originalInterfaceId, int originalFrameNumber, InternetKnoten node) {
        Object[] interfaceIdAndFrameNumber = new Object[2];
        EthernetFrame originalFrame = getFrame(originalInterfaceId, originalFrameNumber);

        Object data = originalFrame.getDaten();
        // Only IP packets can be forwarded
        if (data instanceof IpPaket) {

            // Only execute if the node was not the original sender or receiver of the
            // encapsuled IP packet (e.g. has forwarded the packet)
            if (!packetOnlyReceivedOrOnlySent(originalFrame, node)) {
                List<NetzwerkInterface> netzwerkInterfaces = node.getNetzwerkInterfaces();

                boolean found = false;
                for (NetzwerkInterface netzwerkInterface : netzwerkInterfaces) {
                    String interfaceId = netzwerkInterface.getMac();

                    LinkedList<Object[]> framesMitZeitstempel = datenEinheiten.get(interfaceId);

                    if (framesMitZeitstempel != null) {
                        boolean sent = originalFrame.getQuellMacAdresse().equals(originalInterfaceId);
                        boolean received = originalFrame.getZielMacAdresse().equals(originalInterfaceId);

                        for (int frameNumber = 0; frameNumber < framesMitZeitstempel.size(); frameNumber++) {
                            EthernetFrame frame = (EthernetFrame) framesMitZeitstempel.get(frameNumber)[1];

                            // if the original frame was sent, the TTL of the desired frame (the received
                            // one) has to be one more than the one of the original frame, if received (the
                            // sent one) one less
                            int originalTTL = ((IpPaket) data).getTtl();
                            if (frame.samePayload(originalFrame, originalTTL + 1) && sent
                                    || frame.samePayload(originalFrame, originalTTL - 1) && received) {
                                found = true;
                                interfaceIdAndFrameNumber[0] = (String) interfaceId;
                                interfaceIdAndFrameNumber[1] = (Integer) frameNumber + 1;
                                break;
                            }
                        }
                        if (found) {
                            break;
                        }
                    }
                }
            }
        }
        return interfaceIdAndFrameNumber;
    }

    /**
     * Returns the ethernet frame with the same payload as the frame in the first argument but with a desired TTL. If
     * the frame in the first argument does not encapsule an IP packet (e.g. an ARP packet) the method returns null. If
     * no such frame exists it returns null as well.
     * 
     * @param originalFrame
     *            the frame whose data should be equal to the returned one
     * @param ttl
     *            the desired TTL
     * @return frame with same data and specified TTL (null if it does not exist)
     * @author Christoph Irniger
     */
    public EthernetFrame getFrameWithSameContentAndSpecificTTL(EthernetFrame originalFrame, int ttl) {
        if (originalFrame.getDaten() instanceof IpPaket) {
            for (String interfaceId : getInterfaceIDs()) {
                LinkedList<Object[]> framesMitZeitstempel = datenEinheiten.get(interfaceId);
                if (framesMitZeitstempel != null) {
                    for (Object[] frameMitZeitstempel : framesMitZeitstempel) {
                        EthernetFrame frame = (EthernetFrame) frameMitZeitstempel[1];
                        if (frame.samePayload(originalFrame, ttl)) {
                            return frame;
                        }
                    }
                }
            }
        }
        return null;
    }

    /**
     * This method checks if the node was the original sender or receiver of the layer 2 (IP or ICMP) packet inside the
     * {@code frame}. If this is not the case, we know that the packet was forwarded by this node.
     * 
     * @param frame
     *            The frame of which the layer 2 (IP or ICMP) packet should be checked
     * @param node
     *            The originally selected node
     * @return true oder false
     * @author Christoph Irniger
     */
    private boolean packetOnlyReceivedOrOnlySent(EthernetFrame frame, InternetKnoten node) {
        Object daten = frame.getDaten();
        List<NetzwerkInterface> netzwerkInterfaces = node.getNetzwerkInterfaces();

        if (daten instanceof ArpPaket) {
            return true;
        } else if (daten instanceof IpPaket) {
            for (NetzwerkInterface netzwerkInterface : netzwerkInterfaces) {
                if (((IpPaket) daten).getEmpfaenger().equals(netzwerkInterface.getIp())
                        || ((IpPaket) daten).getSender().equals(netzwerkInterface.getIp())
                        || ((IpPaket) daten).getEmpfaenger().equals("255.255.255.255")) {
                    return true;
                }
            }
            return false;
        } else {
            return false;
        }
    }

    /**
     * This helper method returns the frame in the Lauscher data that belongs to the network interface indicated in the
     * first parameter and the frame number in the data exchange window in the second parameter.
     * 
     * @param interfaceId
     *            MAC address of the network interface whose data exchange should be searched for the frame
     * @param frameNumber
     *            number of the frame in the data exchange window
     * @return frame which belongs to the parameters
     * @author Christoph Irniger
     */
    public EthernetFrame getFrame(String interfaceId, int frameNumber) {
        Object[] frameMitZeitstempel = datenEinheiten.get(interfaceId).get(frameNumber - 1);
        return (EthernetFrame) frameMitZeitstempel[1];
    }

    /**
     * Returns the frame number (number of a frame in the data exchange window of an interface) to a given interface ID
     * and ethernet frame. Returns 0 if the frame was not found.
     * 
     * @param interfaceId
     *            ID of the interface
     * @param frame
     *            frame which the number should be computed for
     * @return the frame number in the data exchange window (starts with 1) or 0 if the frame was not found
     * @author Christoph Irniger
     */
    public int getFrameNumber(String interfaceId, EthernetFrame frame) {
        LinkedList<Object[]> framesMitZeitstempel = datenEinheiten.get(interfaceId);
        if (framesMitZeitstempel != null) {
            for (int frameNumber = 0; frameNumber < framesMitZeitstempel.size(); frameNumber++) {
                if (((EthernetFrame) framesMitZeitstempel.get(frameNumber)[1]).sameContent(frame)) {
                    return frameNumber + 1;
                }
            }
        }
        return 0;
    }

    /**
     * Adds the pair {@code interfaceId} and {@code interface} of type {@code NetzwerkInterface} to the HashMap
     * {@code InterfaceById}.
     * 
     * @param interfaceId
     *            MAC address of the interface
     * @param networkInterface
     *            interface belonging to the interface ID
     * @author Christoph Irniger
     */
    public void storeInterfaceById(String interfaceId, NetzwerkInterface networkInterface) {
        if (!InterfaceById.keySet().contains(interfaceId)) {
            InterfaceById.put(interfaceId, networkInterface);
        }
    }

    /**
     * Adds the pair {@code interfaceId} and {@code systemSoftware} of type {@code SystemSoftware} to the HashMap
     * {@code SystemSoftwareById}.
     * 
     * @param interfaceId
     *            MAC address of the interface
     * @param systemSoftware
     *            systemSoftware (operating system) belonging to the interface ID
     * @author Christoph Irniger
     */
    public void storeSystemSoftwareById(String interfaceId, SystemSoftware systemSoftware) {
        if (!SystemSoftwareById.keySet().contains(interfaceId)) {
            SystemSoftwareById.put(interfaceId, systemSoftware);
        }
    }
}
