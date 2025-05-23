FROM ubuntu:22.04

USER root

ARG PG_VERSION=15  # Default to 15 if not provided

ENV POD_IDENTITY="node1" \
    PATRONI_TTL=60 \
    PATRONI_LOOP_WAIT=10 \
    PATRONI_RETRY_TIMEOUT=40 \
    PATRONI_MAXIMUM_LAG_ON_FAILOVER=1048576 \
    PATRONI_SYNCHRONOUS_MODE="false" \
    PG_CLUST_NAME="common" \
    PG_MAX_CONNECTIONS=200 \
    PG_CONF_MAX_PREPARED_TRANSACTIONS=200 \
    PATRONICTL_CONFIG_FILE="/patroni/pg_node.yml" \
    PG_BIN_DIR="/usr/lib/postgresql/$PG_VERSION/bin/" \
    POSTGRESQL_VERSION=$PG_VERSION \
    LC_ALL=en_US.UTF-8 \
    LANG=en_US.UTF-8 \
    EDITOR=/usr/bin/vi \
    PATH="/usr/lib/postgresql/$PG_VERSION/bin/:${PATH}"

# Official CentOS repos contain libprotobuf-c 1.0.2, but decoderbufs require 1.1+, thus,
# we craft a custom build of protobuf-c and publish it at this repo.
# Remove this line after moving to the next CentOS releases.
COPY scripts/archive_wal.sh /opt/scripts/archive_wal.sh
ADD ./scripts/pip.conf /root/.pip/pip.conf
COPY ./scripts/postgresql.conf /tmp/postgresql.conf
COPY ./scripts/fix_permission.sh /usr/libexec/fix-permissions
ADD ./scripts/* /

RUN echo "deb [trusted=yes] http://apt.postgresql.org/pub/repos/apt jammy-pgdg main" >> /etc/apt/sources.list.d/pgdg.list
RUN ls -la /etc/apt/
RUN apt-get -y update
RUN apt-get -o DPkg::Options::="--force-confnew" -y dist-upgrade
RUN apt-get update && \
    apt-get install -y --allow-downgrades gcc-12 cpp-12 gcc-12-base libgcc-12-dev libstdc++6 libgcc-s1 libnsl2
RUN apt-get --no-install-recommends install -y python3.11 python3-pip python3-dev libpq-dev cython3 wget curl vmtouch

# rename 'tape' group to 'postgres' and creating postgres user - hask for ubuntu
RUN groupmod -n postgres tape
RUN adduser -uid 26 -gid 26 postgres

ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get --no-install-recommends install -y postgresql-$PG_VERSION postgresql-contrib-$PG_VERSION postgresql-server-dev-$PG_VERSION postgresql-plpython3-$PG_VERSION postgresql-$PG_VERSION-hypopg postgresql-$PG_VERSION-powa postgresql-$PG_VERSION-orafce\
    hostname gettext jq vim \
    postgresql-$PG_VERSION-cron postgresql-$PG_VERSION-repack postgresql-$PG_VERSION-pgaudit postgresql-$PG_VERSION-pg-stat-kcache postgresql-$PG_VERSION-pg-qualstats postgresql-$PG_VERSION-set-user postgresql-$PG_VERSION-postgis pgbackrest \
    postgresql-$PG_VERSION-pg-wait-sampling postgresql-$PG_VERSION-pg-track-settings postgresql-$PG_VERSION-pg-hint-plan postgresql-$PG_VERSION-pgnodemx postgresql-$PG_VERSION-decoderbufs

# Install LDAP utilities including openldap-clients and necessary libraries
RUN apt-get update && apt-get install -y \
    ldap-utils \
    libldap-2.5-0 \
    libsasl2-modules-gssapi-mit \
    libldap-common \
    && rm -rf /var/lib/apt/lists/*


RUN localedef -i en_US -f UTF-8 en_US.UTF-8 && \
    localedef -i es_PE -f UTF-8 es_PE.UTF-8 && \
    localedef -i es_ES -f UTF-8 es_ES.UTF-8

RUN wget https://github.com/zubkov-andrei/pg_profile/releases/download/4.8/pg_profile--4.8.tar.gz && \
    tar -xzf pg_profile--4.8.tar.gz --directory $(pg_config --sharedir)/extension && \
    rm -rf pg_profile--4.8.tar.gz

# Install pgsentinel and pg_dbms_stats
RUN apt update && apt-get install -y git make gcc && \
    git clone https://github.com/pgsentinel/pgsentinel.git && \
    cd pgsentinel && \
    git checkout 0218c2147daab0d2dbbf08433cb480163d321839 && \
    cd src && make install && \
    cd ../.. && git clone --depth 1 --branch REL14_0 https://github.com/ossc-db/pg_dbms_stats.git && \
    cd pg_dbms_stats && sed -i 's/$(MAJORVERSION)/14/g' Makefile && \
    make install && \
    apt-get purge -y --auto-remove git make gcc && \
    cd .. && rm -rf pgsentinel

RUN apt-get install -y alien

RUN cat /root/.pip/pip.conf
RUN python3 -m pip install -U setuptools==70.0.0 wheel==0.38.0
RUN python3 -m pip install psutil patroni[kubernetes,etcd]==3.3.5 psycopg2-binary==2.9.5 requests python-dateutil urllib3 six prettytable --no-cache
# Explicitly install patched libaom3 version
RUN apt-get --no-install-recommends install -y libaom3=3.3.0-1ubuntu0.1 || apt-get --no-install-recommends install -y libaom3
RUN mv /var/lib/postgresql /var/lib/pgsql

RUN chgrp 0 /etc &&  \
    chmod g+w /etc && \
    chgrp 0 /etc/passwd &&  \
    chmod g+w /etc/passwd && \
    mkdir /patroni && chmod -R 777 /patroni/ && \
    chmod +x /usr/libexec/fix-permissions && \
    /usr/libexec/fix-permissions /var/run/postgresql && \
    /usr/libexec/fix-permissions /var/lib/pgsql && \
    mkdir -p /var/lib/pgsql/data/ && \
    chown -R postgres:postgres /var/lib/pgsql && \
    chmod +x /*.py && \
    chmod +x /*.sh && \
    chmod 777 /opt/scripts/archive_wal.sh && \
    ln -s /usr/bin/python3 /usr/bin/python

RUN chmod 770 /var/lib/pgbackrest && \
    chmod 770 /var/log/pgbackrest && \
    chmod 770 /var/spool/pgbackrest && \
    chown postgres:0 /var/lib/pgbackrest && \
    chown postgres:0 /var/log/pgbackrest && \
    chown postgres:0 /var/spool/pgbackrest
    
# Volumes are defined to support read-only root file system
VOLUME /etc
VOLUME /patroni
VOLUME /run/postgresql

WORKDIR /patroni
ENTRYPOINT ["/start.sh"]

USER 26
EXPOSE 5432
EXPOSE 8008
