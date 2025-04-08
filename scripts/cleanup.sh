#!/usr/bin/env bash

pg_archivecleanup -d /var/lib/pgsql/data/postgresql_${POD_IDENTITY}/pg_wal/ $1