/******************************************************************
*
*	CyberLink for C
*
*	Copyright (C) Satoshi Konno 2005
*
*	File: chttpmu_socket.c
*
*	Revision:
*
*	06/10/05
*		- first revision
*
******************************************************************/

#include <cybergarage/upnp/ssdp/cssdp_server.h>

/****************************************
* cg_upnp_httpu_socket_recv
****************************************/

int cg_upnp_httpu_socket_recv(CgUpnpHttpMuSocket *sock, CgUpnpSSDPPacket *ssdpPkt)
{
	CgDatagramPacket *dgmPkt;
	char *ssdpData;
	int recvLen;
	
	dgmPkt = cg_upnp_ssdp_packet_getdatagrampacket(ssdpPkt);
	recvLen = cg_socket_recv(sock, dgmPkt);
	
	if (recvLen <= 0)
		return recvLen;

	ssdpData = cg_socket_datagram_packet_getdata(dgmPkt);
	cg_upnp_ssdp_packet_setheader(ssdpPkt, ssdpData);
	 cg_socket_datagram_packet_setdata(dgmPkt, NULL);
	
	return recvLen;
}
