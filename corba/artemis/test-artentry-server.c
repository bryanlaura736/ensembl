#include "artemis-mysql-impl.h"
#include <stdio.h>
#include <signal.h>
#include <stdlib.h>
#include <mysql/mysql.h>



int main (int argc, char *argv[])
{
    PortableServer_ObjectId objid = {0, sizeof("EnsemblTestServer"), "EnsemblTestServer"};
    PortableServer_POA poa;
    FILE * ifp;
    CORBA_Environment ev;
    char *retval;
    CORBA_ORB orb;
    Ensembl_artemis_Entry en;

    MYSQL *connection,mysql;

    SimpleObjectManager * som;
    SimpleObjectManagerAdaptor soma;

    fprintf(stderr,"Got in...\n");
    mysql_init(&mysql);
    connection = mysql_real_connect(&mysql,"localhost","root",0,"ensdev",0,0,0);

    fprintf(stderr,"Connected...\n");

    signal(SIGINT, exit);
    signal(SIGTERM, exit);

    CORBA_exception_init(&ev);
    orb = CORBA_ORB_init(&argc, argv, "orbit-local-orb", &ev);

    poa = (PortableServer_POA)CORBA_ORB_resolve_initial_references(orb, "RootPOA", &ev);
    PortableServer_POAManager_activate(PortableServer_POA__get_the_POAManager(poa, &ev), &ev);

    som = new_SimpleObjectManager(stderr,0,0,60,"test-entry",60,1,0,&ev);
    soma = SimpleObjectManager_get_Adaptor(som);

    fprintf(stderr,"About to make...\n");
    en = new_Ensembl_artemis_Entry(poa,connection,argv[1],soma,&ev);
    fprintf(stderr,"Made...\n");
    retval = CORBA_ORB_object_to_string(orb, en, &ev);
    ifp = fopen("entry.ior","w");
    fprintf(ifp,"%s\n", retval); 
    fclose(ifp);

    CORBA_free(retval);

    fprintf(stderr,"Waiting for Entry requests...\n");
    CORBA_ORB_run(orb, &ev);
    return 0;
}

