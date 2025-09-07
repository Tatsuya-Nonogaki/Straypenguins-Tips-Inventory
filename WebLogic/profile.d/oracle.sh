if [ "$USER" = "oracle" ]; then
    umask 027
    ORACLE_HOME=/opt/oracle/Middleware/Oracle_Home
    WL_HOME=${ORACLE_HOME}/wlserver
    DOMAIN_HOME=/opt/oracle/user_projects/domains/base_domain
    export ORACLE_HOME WL_HOME DOMAIN_HOME
    unset USERNAME

    ulimit -Su 5120
    ulimit -Sn 10240
fi
