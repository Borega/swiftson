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
package filius.software.vermittlungsschicht;

/** Diese Klasse umfasst die Attribute eines ICMP-Pakets */
@SuppressWarnings("serial")
public class IcmpPaket extends IpPaket {

    public static final int ICMP_PROTOCOL = 1;
    /**
     * identifier of Echo Request packet: The identifier is used by the router in place of the port by Echo Requests and Responses
     */
    private int identifier;
    /**
     * sequence number of Echo Request packet: The sequence number can be used by the client to associate each echo
     * request with its reply.
     */
    private int seqNr;
    /**
     * 0: ICMP Echo Reply (pong) <br />
     * 3: see {@link #icmpType} <br />
     * 8: ICMP Echo Request (ping)<br />
     * 11: ICMP Time Exceeded (poof) <br />
     * else: ICMP unknown
     */
    private int icmpType;
    /**
     * 0: "ICMP Network Unreachable <br />
     * 1: ICMP Host Unreachable <br />
     * other: ICMP Destination Unreachable
     */
    private int icmpCode;
    
    private IpPaket payload;

    public IcmpPaket(long identification) {
        super(ICMP_PROTOCOL, identification);
    }

    @Override
    public IcmpPaket clone() {
        IcmpPaket clone = new IcmpPaket(getIdentification());
        copyIpPacketAttributes(clone);
        copyIcmpAttributes(clone);
        return clone;
    }

    private void copyIcmpAttributes(IcmpPaket clone) {
    	clone.identifier = identifier;
        clone.seqNr = seqNr;
        clone.icmpType = icmpType;
        clone.icmpCode = icmpCode;
        clone.payload = payload;
    }

    public void setIcmpType(int type) {
        this.icmpType = type;
    }

    public void setIcmpCode(int code) {
        this.icmpCode = code;
    }
    
    public void setPayload(IpPaket payload) {
    	if(!(payload instanceof IcmpPaket)) {
    		payload.getSegment().setDaten(null);
    	}
    	this.payload = payload;
    }

    public int getIcmpType() {
        return icmpType;
    }

    public int getIcmpCode() {
        return icmpCode;
    }
    
    public IpPaket getPayload() {
    	return payload;
    }

    public boolean isEchoResponse() {
        return icmpType == ICMP.TYPE_ECHO_REPLY && icmpCode == ICMP.CODE_ECHO;
    }

    public boolean isEchoRequest() {
        return icmpType == ICMP.TYPE_ECHO_REQUEST && icmpCode == ICMP.CODE_ECHO;
    }

    public int getSeqNr() {
        return this.seqNr;
    }

    public void setSeqNr(int seqNr) {
        this.seqNr = seqNr;
    }

    public int getIdentifier() {
        return this.identifier;
    }

    public void setIdentifier(int identifier) {
        this.identifier = identifier;
    }

    public String toString() {
        return "[" + "id=" + getIdentification() + "; " + "ttl=" + getTtl() + "; " + "protocol="+ getProtocol() +"; " + "sender=" + getSender() + "; " + "target=" + getEmpfaenger() + "; "
        		+ "icmpType=" + icmpType + "; " + "icmpCode=" + icmpCode + "; "+ "identifier=" + identifier + "; " + "seqNr=" + seqNr + 
        		(payload != null? ", " + "payload:" + payload : "") + "]";
    }
}
