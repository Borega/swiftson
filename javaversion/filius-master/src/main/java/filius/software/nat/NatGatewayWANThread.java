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
package filius.software.nat;

import filius.software.vermittlungsschicht.IcmpPaket;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import filius.hardware.NetzwerkInterface;
import filius.rahmenprogramm.I18n;
import filius.rahmenprogramm.nachrichten.Lauscher;
import filius.software.firewall.FirewallThread;
import filius.software.netzzugangsschicht.EthernetFrame;
import filius.software.system.SystemSoftware;
import filius.software.vermittlungsschicht.IpPaket;
import filius.software.vermittlungsschicht.VermittlungsProtokoll;

public class NatGatewayWANThread extends FirewallThread implements I18n {
    private static Logger LOG = LoggerFactory.getLogger(NatGatewayWANThread.class);
    private NatGateway natGateway;

    private NetzwerkInterface lanNic;
    private NetzwerkInterface wanNic;

    /**
     * Init thread for the WAN network interface
     */
    public NatGatewayWANThread(NatGateway natGateway, NetzwerkInterface nic, NetzwerkInterface lanNic,
                               SystemSoftware systemSoftware) {
        super(natGateway, nic, systemSoftware);
        this.natGateway = natGateway;
        this.wanNic = nic;
        this.lanNic = lanNic;
    }

    @Override
    protected void verarbeiteDatenEinheit(EthernetFrame frame) {
        Lauscher.getLauscher().addDatenEinheit(wanNic, systemSoftware, frame);
        boolean applyNATForwarding = true;
        boolean isPingToWAN = false;
        if (frame.getDaten() instanceof IpPaket) {
            IpPaket packet = (IpPaket) frame.getDaten();
            if (!(packet instanceof IcmpPaket)) {
                applyNATForwarding = natGateway.eintragExistiert(packet);
            } else if (((IcmpPaket) packet).isEchoRequest()) {
                isPingToWAN = true;
            } else if (((IcmpPaket) packet).isEchoResponse()) {
                applyNATForwarding = natGateway.eintragExistiert(packet);
            }
        }
        if (isPingToWAN) {
            natGateway.getSystemSoftware().holeICMP().sendEchoReply((IcmpPaket) frame.getDaten());
            LOG.debug("Reply ping to home router: {}", frame);
        } else if (checkToLANAddress(frame)) {
            LOG.debug("Discarded frame addressed to LAN address but received on WAN port: {}", frame);
        } else if (checkDiscardByFirewall(frame)) {
            LOG.debug("Discarded frame by firewall: {}", frame);
        } else if (applyNATForwarding) {
            forwardFrame(modifyIncomingFrame(frame));
        } else {
            forwardFrame(frame);
        }
    }

    private EthernetFrame modifyIncomingFrame(EthernetFrame frame) {
        EthernetFrame modifiedFrame = frame.clone();
        if (modifiedFrame.getDaten() instanceof IpPaket) {
            IpPaket packet = (IpPaket) modifiedFrame.getDaten();
            if (packet.getEmpfaenger().contentEquals(wanNic.getIp())) {
                natGateway.replaceDestination(packet);
            }
        }
        return modifiedFrame;
    }

    private boolean checkToLANAddress(EthernetFrame frame) {
        boolean toLANAddress = false;
        if (null != lanNic && frame.getDaten() instanceof IpPaket) {
            IpPaket packet = (IpPaket) frame.getDaten();
            if (VermittlungsProtokoll.gleichesRechnernetz(packet.getEmpfaenger(), lanNic.getIp(),
                lanNic.getSubnetzMaske())) {
                toLANAddress = true;
            }
        }
        return toLANAddress;
    }
}
