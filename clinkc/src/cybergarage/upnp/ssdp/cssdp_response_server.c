/******************************************************************
*
*	CyberLink for C
*
*	Copyright (C) Satoshi Konno 2005
*
*	File: cssdp_socket.c
*
*	Revision:
*
*	02/18/05
*		- first revision
*
******************************************************************/

#include <cybergarage/upnp/ssdp/cssdp_server.h>
#include <cybergarage/net/cinterface.h>

/****************************************
* CG_UPNP_NOUSE_CONTROLPOINT (Begin)
****************************************/

#if !defined(CG_UPNP_NOUSE_CONTROLPOINT)

/****************************************
* cg_upnp_ssdpresponse_server_new
****************************************/

CgUpnpSSDPResponseServer *cg_upnp_ssdpresponse_server_new()
{
	CgUpnpSSDPResponseServer *server = (CgUpnpSSDPResponseServer *)malloc(sizeof(CgUpnpSSDPResponseServer));
	cg_list_node_init((CgList *)server);

	server->httpuSock = NULL;
	server->recvThread = NULL;

	cg_upnp_ssdpresponse_server_setlistener(server, NULL);
	cg_upnp_ssdpresponse_server_setuserdata(server, NULL);
	
	return server;
}

/****************************************
* cg_upnp_ssdpresponse_server_delete
****************************************/

void cg_upnp_ssdpresponse_server_delete(CgUpnpSSDPResponseServer *server)
{
	cg_upnp_ssdpresponse_server_stop(server);
	cg_upnp_ssdpresponse_server_close(server);
	
	cg_list_remove((CgList *)server);

	free(server);
}

/****************************************
* cg_upnp_ssdpresponse_server_open
****************************************/

BOOL cg_upnp_ssdpresponse_server_open(CgUpnpSSDPResponseServer *server, int bindPort, char *bindAddr)
{
	if (cg_upnp_ssdpresponse_server_isopened(server) == TRUE)
		return FALSE;
		
	server->httpuSock = cg_upnp_httpu_socket_new();
	if (cg_upnp_httpu_socket_bind(server->httpuSock, bindPort, bindAddr) == FALSE) {
		cg_upnp_httpu_socket_delete(server->httpuSock);
		server->httpuSock = NULL;
		return FALSE;
	}
	
	return TRUE;
}

/****************************************
* cg_upnp_ssdpresponse_server_close
****************************************/

BOOL cg_upnp_ssdpresponse_server_close(CgUpnpSSDPResponseServer *server)
{
	cg_upnp_ssdpresponse_server_stop(server);
	
	if (server->httpuSock != NULL) {
		cg_upnp_httpu_socket_close(server->httpuSock);
		cg_upnp_httpu_socket_delete(server->httpuSock);
		server->httpuSock = NULL;
	}
	
	return TRUE;
}

/****************************************
* cg_upnp_ssdpresponse_server_performlistener
****************************************/

void cg_upnp_ssdpresponse_server_performlistener(CgUpnpSSDPResponseServer *server, CgUpnpSSDPPacket *ssdpPkt)
{
	CG_UPNP_SSDP_RESPONSE_LISTNER listener = cg_upnp_ssdpresponse_server_getlistener(server);
	if (listener == NULL)
		return;
	listener(ssdpPkt);
}

/****************************************
* cg_upnp_ssdpresponse_server_thread
****************************************/

static void cg_upnp_ssdpresponse_server_thread(CgThread *thread)
{
	CgUpnpSSDPResponseServer *server;
	CgUpnpSSDPPacket *ssdpPkt;
	void *userData;
	
	server = (CgUpnpSSDPResponseServer *)cg_thread_getuserdata(thread);
	userData = cg_upnp_ssdpresponse_server_getuserdata(server);
	
	if (cg_upnp_ssdpresponse_server_isopened(server) == FALSE)
		return;

	ssdpPkt = cg_upnp_ssdp_packet_new();
	cg_upnp_ssdp_packet_setuserdata(ssdpPkt, userData);
	
	while (cg_thread_isrunnable(thread) == TRUE) {
		if (cg_upnp_httpu_socket_recv(server->httpuSock, ssdpPkt) <= 0)
			break;

		cg_upnp_ssdpresponse_server_performlistener(server, ssdpPkt);
		cg_upnp_ssdp_packet_clear(ssdpPkt);
	}
	
	cg_upnp_ssdp_packet_delete(ssdpPkt);
}

/****************************************
* cg_upnp_ssdpresponse_server_start
****************************************/

BOOL cg_upnp_ssdpresponse_server_start(CgUpnpSSDPResponseServer *server)
{
	if (server->recvThread != NULL)
		return FALSE;
		
	server->recvThread = cg_thread_new();
	cg_thread_setaction(server->recvThread, cg_upnp_ssdpresponse_server_thread);
	cg_thread_setuserdata(server->recvThread, server);
	if (cg_thread_start(server->recvThread) == FALSE) {	
		cg_thread_delete(server->recvThread);
		server->recvThread = NULL;
		return FALSE;
	}
	
	return TRUE;
}

/****************************************
* cg_upnp_ssdpresponse_server_stop
****************************************/

BOOL cg_upnp_ssdpresponse_server_stop(CgUpnpSSDPResponseServer *server)
{
	if (server->recvThread != NULL) {
		cg_thread_stop(server->recvThread);
		cg_thread_delete(server->recvThread);
		server->recvThread = NULL;
	}
	return TRUE;
}

/****************************************
* cg_upnp_ssdpresponse_server_post
****************************************/

BOOL cg_upnp_ssdpresponse_server_post(CgUpnpSSDPResponseServer *server, CgUpnpSSDPRequest *ssdpReq)
{
	CgUpnpHttpUSocket *httpuSock;
	char *ifAddr;
	char *ssdpAddr;
	CgString *ssdpMsg;
	
	httpuSock = cg_upnp_ssdpresponse_server_getsocket(server);
	
	ifAddr = cg_socket_getaddress(httpuSock);
	ssdpAddr = cg_upnp_ssdp_gethostaddress(ifAddr);
	cg_upnp_ssdprequest_sethost(ssdpReq, ssdpAddr, CG_UPNP_SSDP_PORT);
		
	ssdpMsg = cg_string_new();
	cg_upnp_ssdprequest_tostring(ssdpReq, ssdpMsg);
	cg_socket_sendto(httpuSock, ssdpAddr, CG_UPNP_SSDP_PORT, cg_string_getvalue(ssdpMsg), cg_string_length(ssdpMsg));
	cg_string_delete(ssdpMsg);
	
	return TRUE;
}

/****************************************
* CG_UPNP_NOUSE_CONTROLPOINT (End)
****************************************/

#endif
