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

import java.util.ArrayList;
import java.util.LinkedList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.hardware.NetzwerkInterface;
import filius.hardware.knoten.InternetKnoten;
import filius.rahmenprogramm.nachrichten.Lauscher;
import filius.software.ProtocolDataUnit;
import filius.software.Protokoll;
import filius.software.system.SystemSoftware;
import filius.software.vermittlungsschicht.ArpPaket;
import filius.software.vermittlungsschicht.IcmpPaket;
import filius.software.vermittlungsschicht.IpPaket;

/** Diese Klasse implementiert die Netzzugangsschicht */
public class Ethernet extends Protokoll {
    private static Logger LOG = LoggerFactory.getLogger(Ethernet.class);

    public static final String ETHERNET_BROADCAST = "FF:FF:FF:FF:FF:FF";

    /**
     * Liste der Threads fuer die Ueberwachung der Netzwerkkarten
     */
    private LinkedList<EthernetThread> threads = new LinkedList<EthernetThread>();

    /** Puffer fuer eingehende ARP-Pakete */
    private LinkedList<ArpPaket> arpPakete = new LinkedList<ArpPaket>();

    /** Puffer fuer eingehende IP-Pakete */
    private LinkedList<IpPaket> ipPakete = new LinkedList<IpPaket>();

    /** Puffer fuer eingehende ICMP-Pakete */
    private LinkedList<IcmpPaket> icmpPakete = new LinkedList<IcmpPaket>();

    /** Konstruktor zur Initialisierung der Systemsoftware */
    public Ethernet(SystemSoftware systemSoftware) {
        super(systemSoftware);
        LOG.trace("INVOKED-2 (" + this.hashCode() + ") " + getClass() + " (Ethernet), constr: Ethernet("
                + systemSoftware + ")");
    }

    /** Methode fuer den Zugriff auf den Puffer mit ARP-Paketen */
    public LinkedList<ArpPaket> holeARPPuffer() {
        return arpPakete;
    }

    /** Methode fuer den Zugriff auf den Puffer mit IP-Paketen */
    public LinkedList<IpPaket> holeIPPuffer() {
        return ipPakete;
    }

    /** Methode fuer den Zugriff auf den Puffer mit ICMP-Paketen */
    public LinkedList<IcmpPaket> holeICMPPuffer() {
        return icmpPakete;
    }

    /** Methode fuer den Zugriff auf den Puffer mit IP-Paketen */
    public void setzeIPPuffer(LinkedList<IpPaket> puffer) {
        ipPakete = puffer;
    }

    /**
     * Sendet Pakete als Ethernet-Frame weiter. Zuerst wird dazu ueberprueft, ob die Ziel-MAC-Adresse eine eigene
     * Netzwerkkarte adressiert. Wenn dies nicht der Fall ist, wird der Frame ueber die Netzwerkkarte verschickt, die
     * durch die Quell-MAC-Adresse spezifiziert wird.
     * 
     * @param useNic
     *            the network interface controller with which the PDU must be sent
     */
    public void senden(ProtocolDataUnit daten, String startMAC, String zielMAC, String typ, NetzwerkInterface useNic) {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + " (Ethernet), senden(" + daten + "," + startMAC
                + "," + zielMAC + "," + typ + ")");

        EthernetFrame ethernetFrame = new EthernetFrame(daten, startMAC, zielMAC, typ);
        List<NetzwerkInterface> senderNICs = new ArrayList<>();
        if (null != useNic) {
            LOG.trace("Ethernet: send via specific nic {}", useNic);
            senderNICs.add(useNic);
        }

        // I do not understand the purpose of this code. It should never be used!
        if (senderNICs.isEmpty()) {
            for (NetzwerkInterface nic : ((InternetKnoten) holeSystemSoftware().getKnoten()).getNetzwerkInterfaces()) {
                if (nic.getMac().equalsIgnoreCase(zielMAC)) {
                    LOG.error("Ethernet: send via nic selected by target MAC ({})", zielMAC);
                    senderNICs.add(nic);
                }
            }
        }

        if (senderNICs.isEmpty()) {
            for (NetzwerkInterface nic : ((InternetKnoten) holeSystemSoftware().getKnoten()).getNetzwerkInterfaces()) {
                if (nic.getMac().equalsIgnoreCase(startMAC)) {
                    senderNICs.add(nic);
                }
            }
        }

        for (NetzwerkInterface nic : senderNICs) {
            synchronized (nic.getPort().holeAusgangsPuffer()) {
                nic.getPort().holeAusgangsPuffer().add(ethernetFrame);
                nic.getPort().holeAusgangsPuffer().notify();
            }
            Lauscher.getLauscher().addDatenEinheit(nic, holeSystemSoftware(), ethernetFrame);
        }
    }

    public LinkedList<EthernetThread> getEthernetThreads() {
        return threads;
    }

    /**
     * Hier wird zu jeder Netzwerkkarte ein Thread zur Ueberwachung des Eingangspuffers gestartet.
     */
    public void starten() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + " (Ethernet), starten()");
        InternetKnoten knoten;
        EthernetThread interfaceBeobachter;

        // ensure that there are no pdu's left from last run!
        if (arpPakete.size() > 0) {
            LOG.debug("Clear ARP buffer. Still data left from last run.");
            arpPakete.clear();
        }
        if (icmpPakete.size() > 0) {
            LOG.debug("Clear ICMP buffer. Still data left from last run.");
            icmpPakete.clear();
        }
        if (ipPakete.size() > 0) {
            LOG.debug("Clear IP buffer. Still data left from last run.");
            ipPakete.clear();
        }

        if (holeSystemSoftware().getKnoten() instanceof InternetKnoten) {
            knoten = (InternetKnoten) holeSystemSoftware().getKnoten();

            for (NetzwerkInterface nic : knoten.getNetzwerkInterfaces()) {
                interfaceBeobachter = new EthernetThread(this, nic, holeSystemSoftware());
                interfaceBeobachter.starten();
                try {
                    threads.add(interfaceBeobachter);
                } catch (Exception e) {
                    LOG.debug("", e);
                }
            }
        }
    }

    /**
     * beendet alle laufenden EthernetThreads zur Ueberwachung der Eingangspuffer der Netzwerkkarten
     */
    public void beenden() {
        LOG.trace("INVOKED (" + this.hashCode() + ") " + getClass() + " (Ethernet), beenden()");
        EthernetThread interfaceBeobachter;

        for (int x = 0; x < threads.size(); x++) {
            interfaceBeobachter = (EthernetThread) threads.get(x);
            interfaceBeobachter.beenden();
        }
    }
}
