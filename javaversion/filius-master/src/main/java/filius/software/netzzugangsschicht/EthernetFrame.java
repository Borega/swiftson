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
package filius.software.netzzugangsschicht;

import java.util.HashSet;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.software.ProtocolDataUnit;
import filius.software.vermittlungsschicht.ArpPaket;
import filius.software.vermittlungsschicht.IcmpPaket;
import filius.software.vermittlungsschicht.IpPaket;

/**
 * Diese Klasse implementiert einen Frame auf der Netzzugangsschicht.
 */
public class EthernetFrame extends ProtocolDataUnit {
    private static Logger LOG = LoggerFactory.getLogger(EthernetFrame.class);

    private static final long serialVersionUID = 1L;

    /** Protokolltypen der Vermittlungsschicht */
    public static final String IP = "0x800", ARP = "0x806";

    /** Die Ziel-Adresse des Frames */
    private String zielMacAdresse;

    /** Die MAC-Adresse, von dem sendenden Rechner */
    private String quellMacAdresse;

    /** Typ des uebergeordneten Protokolls (ARP oder IP) */
    private String typ;

    /** die Nutzdaten */
    private ProtocolDataUnit daten;

    private Set<String> readByLauscherForMac = new HashSet<>();

    /** Konstruktor zur Initialisierung der Attribute des Frames */
    public EthernetFrame(ProtocolDataUnit daten, String quellMacAdresse, String zielMacAdresse, String typ) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + " (EthernetFrame), constr: EthernetFrame(" + daten
                + "," + quellMacAdresse + "," + zielMacAdresse + "," + typ + ")");
        this.zielMacAdresse = zielMacAdresse;
        this.quellMacAdresse = quellMacAdresse;
        this.typ = typ;
        this.daten = daten;
    }

    public EthernetFrame clone() {
        ProtocolDataUnit clonedData;
        if (daten instanceof IcmpPaket) {
            clonedData = ((IcmpPaket) daten).clone();
        } else if (daten instanceof IpPaket) {
            clonedData = ((IpPaket) daten).clone();
        } else {
            clonedData = daten;
        }
        EthernetFrame clonedFrame = new EthernetFrame(clonedData, quellMacAdresse, zielMacAdresse, typ);
        clonedFrame.readByLauscherForMac = readByLauscherForMac;
        clonedFrame.setRcvNic(getRcvNic());
        return clonedFrame;
    }

    public void setReadByLauscherForMac(String mac) {
        readByLauscherForMac.add(mac);
    }

    public boolean isReadByLauscherForMac(String mac) {
        return readByLauscherForMac.contains(mac);
    }

    /** Zugriff auf die Daten, die mit dem Frame verschickt werden */
    public ProtocolDataUnit getDaten() {
        return daten;
    }

    /** Zugriff auf die Absender-MAC-Adresse */
    public String getQuellMacAdresse() {
        return quellMacAdresse;
    }

    /** Zugriff auf den Protokolltyp. Zulaessig sind ARP und IP */
    public String getTyp() {
        return typ;
    }

    /** Methode fuer den Zugriff auf die Ziel-MAC-Adresse */
    public String getZielMacAdresse() {
        return zielMacAdresse;
    }

    public String toString() {
        return "[" + "src=" + quellMacAdresse + ", " + "dest=" + zielMacAdresse + ", " + "type=" + typ
                + (daten != null ? " | " + daten : "") + "]";
    }

    /**
     * Checks if the whole content (which consists of {@code zielMacAdresse}, {@code quellMacAdresse} and {@code daten})
     * of <i>this</i> frame is equal to the frame in the argument.
     * 
     * @param frame
     *            frame to be compared to <i>this</i> frame
     * @return true if zielMacAdresse, quellMacAdresse and daten are equal
     * @author Christoph Irniger
     */
    public boolean sameContent(EthernetFrame frame) {
        if (frame == this) {
            return true;
        }

        // check header
        if (zielMacAdresse.equals(frame.getZielMacAdresse()) && quellMacAdresse.equals(frame.getQuellMacAdresse())
                && typ.equals(frame.getTyp())) {

            Object argumentData = frame.getDaten();
            // check payload
            if (daten instanceof IpPaket && argumentData instanceof IpPaket) {
                IpPaket argumentPacket = (IpPaket) argumentData;
                IpPaket thisPacket = (IpPaket) daten;
                return thisPacket.getIdentification() == argumentPacket.getIdentification()
                        && thisPacket.getTtl() == argumentPacket.getTtl();
            } else if (daten instanceof ArpPaket && argumentData instanceof ArpPaket) {
                ArpPaket thisArpPacket = (ArpPaket) daten;
                ArpPaket argumentArpPacket = (ArpPaket) frame.getDaten();
                return thisArpPacket.getArpPacketNumber() == argumentArpPacket.getArpPacketNumber();
            } else {
                return false;
            }
        } else {
            return false;
        }
    }

    /**
     * If <i>this</i> frame and the frame in the first argument both encapsule an IP packet, this method checks if the
     * packets have the same content and if the IP packet inside <i>this</i> frame has a specific TTL.
     * 
     * @param frame
     *            the frame whose payload should be compared to <i>this</i> payload
     * @param ttl
     *            the desired TTL of <i>this</i> frame in the first argument
     * @return true if the frame in the first argument has the same payload and the specified TTL
     * @author Christoph Irniger
     */
    public boolean samePayload(EthernetFrame frame, int ttl) {
        Object framePayload = frame.getDaten();

        // if both frames are of type IP
        if (daten instanceof IpPaket && framePayload instanceof IpPaket) {
            if (!(daten instanceof IcmpPaket) && !(framePayload instanceof IcmpPaket)) {
                IpPaket thisIpPacket = (IpPaket) daten;
                IpPaket argumentIpPacket = (IpPaket) framePayload;
                return thisIpPacket.getIdentification() == argumentIpPacket.getIdentification()
                        && thisIpPacket.getTtl() == ttl;
            } else if (daten instanceof IcmpPaket && framePayload instanceof IcmpPaket) {
                IcmpPaket thisIcmpPacket = (IcmpPaket) daten;
                IcmpPaket argumentIcmpPacket = (IcmpPaket) framePayload;
                return thisIcmpPacket.getIdentification() == argumentIcmpPacket.getIdentification()
                        && thisIcmpPacket.getTtl() == ttl;
            } else {
                return false;
            }
        } else {
            return false;
        }
    }
}
