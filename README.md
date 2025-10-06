## Deloy on RedHat 9.2
![img.png](img.png)

### add hosts
    10.84.2.40 d-postgres-01
    10.84.2.43 vip
    10.84.2.41 d-postgres-02
    10.84.2.42 d-postgres-03

### install haproxy keepalived on all nodes

    yum install haproxy keepalived -y


### config keepalive

##### d-postgres-01 node

    # create new
    global_defs {
        # set hostname
        router_id LVS_DEVEL
    }
    
    vrrp_instance VRRP1 {
        # on primary node, specify [MASTER]
        # on backup node, specify [BACKUP]
        # if specified [BACKUP] + [nopreempt] on all nodes, automatic failback is disabled
        state MASTER
        # if you like disable automatic failback, set this value with [BACKUP]
        # nopreempt
        # network interface that virtual IP address is assigned
        interface ens192
        # set unique ID on each VRRP interface
        # on the a VRRP interface, set the same ID on all nodes
        virtual_router_id 101
        # set priority : [Master] > [BACKUP]
        priority 200
        # VRRP advertisement interval (sec)
        advert_int 1
        # virtual IP address
        virtual_ipaddress {
            10.84.2.43/24
        }
    }

#### d-postgres-02 node

    # create new
    global_defs {
        router_id LVS_DEVEL
    }
    
    vrrp_instance VRRP1 {
        state BACKUP
        # nopreempt
        interface ens192
        virtual_router_id 101
        priority 100
        advert_int 1
        virtual_ipaddress {
            10.84.2.43/24
        }
    }
#### d-postgres-03 node
    # create new

    global_defs {
        router_id LVS_DEVEL
    }
    
    vrrp_instance VRRP1 {
        state BACKUP
        # nopreempt
        interface ens192
        virtual_router_id 101
        priority 95
        advert_int 1
        virtual_ipaddress {
            10.84.2.43/24
        }
    }


    dnf install https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm -y
    dnf install postgresql16-server postgresql-contrib postgresql16-devel -y
    yum install https://download.postgresql.org/pub/repos/yum/16/redhat/rhel-9-x86_64/system_stats_16-3.2-1PGDG.rhel9.x86_64.rpm
    
    dnf install postgresql16-server postgresql-contrib -y
    
    sudo ln -s /usr/pgsql-16/bin/* /usr/sbin

- install pgaudit
  

    https://github.com/pgaudit/pgaudit/tree/REL_17_STABLE

### ETCD install on all node

    ETCD_RELEASE=$(curl -s https://api.github.com/repos/etcd-io/etcd/releases/latest|grep tag_name | cut -d '"' -f 4)
    echo $ETCD_RELEASE
    wget https://github.com/etcd-io/etcd/releases/download/${ETCD_RELEASE}/etcd-${ETCD_RELEASE}-linux-amd64.tar.gz
    tar xvf etcd-${ETCD_RELEASE}-linux-amd64.tar.gz
    cd etcd-${ETCD_RELEASE}-linux-amd64
    mv etcd* /usr/local/bin 
    ls /usr/local/bin
    etcd --version
    etcdctl version
    etcdutl version
    mkdir -p /var/lib/etcd

    {
    NODE_IP="10.84.2.42"
    
    ETCD_NAME=$(hostname -s)
    
    ETCD1_IP="10.84.2.40"
    ETCD2_IP="10.84.2.41"
    ETCD3_IP="10.84.2.42"
    
    cat <<EOF >/etc/etcd/etcd.conf
    #[member]
    ETCD_NAME=${ETCD_NAME}
    ETCD_DATA_DIR="/var/lib/etcd/data"
    ETCD_LISTEN_PEER_URLS="http://${NODE_IP}:2380"
    ETCD_LISTEN_CLIENT_URLS="http://${NODE_IP}:2379,http://127.0.0.1:2379"
    #[cluster]
    ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${NODE_IP}:2380"
    ETCD_ADVERTISE_CLIENT_URLS="http://${NODE_IP}:2379"
    ETCD_INITIAL_CLUSTER="d-postgres-01=http://${ETCD1_IP}:2380,d-postgres-02=http://${ETCD2_IP}:2380,d-postgres-03=http://${ETCD3_IP}:2380"
    ETCD_LOG_OUTPUTS="/var/log/etcd/etcd.log"
    ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
    ETCD_INITIAL_CLUSTER_STATE NEW
    ETCD_SNAPSHOT_COUNT="10000"
    ETCD_WAL_DIR="/var/lib/etcd/wal"
    ETCD_ENABLE_V2="true"

    ETCD_HEARTBEAT_INTERVAL="200"
    ETCD_ELECTION_TIMEOUT="2000"
    ETCD_LOGGER="zap"
    ETCD_QUOTA_BACKEND_BYTES="8589934592"

    
    EOF
    }

    cat <<EOF >/etc/systemd/system/etcd.service
    [Unit]
    Description=etcd key-value store
    Documentation=https://github.com/etcd-io/etcd
    After=network.target
    
    [Service]
    Type=notify
    EnvironmentFile=/etc/etcd/etcd.conf
    ExecStart=/usr/local/sbin/etcd
    Restart=always
    RestartSec=10s
    LimitNOFILE=40000
    
    [Install]
    WantedBy=multi-user.target
    
    EOF

#### check etcd
    etcdctl \
      member list \
      -w=table
    
    
    etcdctl  endpoint --cluster status -w table


### Install patroni on node1,node2,node3

    yum install python3-devel python3-pip libpq-devel
    
    
    pip3 install --proxy http://10.86.102.94:3128 --upgrade pip
    pip install --proxy http://10.86.102.94:3128 wheel
    pip install --proxy http://10.86.102.94:3128 patroni
    pip install --proxy http://10.86.102.94:3128 python-etcd
    pip install --proxy http://10.86.102.94:3128 psycopg2


#### patroni on all nodes

NOTE: Change ${NODE_NAME} and ${NODE_IP} the same infor on node

    mkdir -p /etc/patroni
    
    
    echo "
    namespace: percona_lab
    scope: cluster_1
    name: ${NODE_NAME}
    
    restapi:
        listen: 0.0.0.0:8008
        connect_address: ${NODE_IP}:8008
    
    etcd:
        host: ${NODE_IP}:2379
    
    bootstrap:
      # this section will be written into Etcd:/<namespace>/<scope>/config after initializing new cluster
      dcs:
         ttl: 30
         loop_wait: 10
         retry_timeout: 10
         maximum_lag_on_failover: 1048576
         slots:
           replica:
             database: postgres
         plugin: pgoutput
         type: phisycal
         postgresql:
             use_pg_rewind: true
             use_slots: true
             remove_data_directory_on_rewind_failure: true
             parameters:
            archive_mode: on
            archive_command: 'pgbackrest --stanza=cluster_1 archive-push %p'
            restore_command: "pgbackrest --stanza=cluster_1 archive-get %f %p"
            max_connections: 5000
            shared_buffers: 2GB
            effective_cache_size: 2GB
            maintenance_work_mem: 1GB
            checkpoint_completion_target: 0.9
            wal_buffers: 16MB
            default_statistics_target: 100
            random_page_cost: 1.1
            effective_io_concurrency: 200
            work_mem: 1048kB
            huge_pages: off
            min_wal_size: 2GB
            max_wal_size: 8GB
            max_worker_processes: 16
            max_parallel_workers_per_gather: 4
            max_parallel_workers: 16
            max_parallel_maintenance_workers: 4
            datestyle: 'iso, ymd'
            timezone: 'Asia/Ho_Chi_Minh'
            default_text_search_config: 'pg_catalog.english'
            shared_preload_libraries: 'pgaudit,pg_stat_statements'
            #shared_preload_libraries: 'pgaudit'
            pg_stat_statements.max: 10000
            pg_stat_statements.track: all
            track_activity_query_size: 2048
            autovacuum_max_workers: 5
            autovacuum_naptime: 30
            autovacuum_vacuum_threshold: 50
            autovacuum_vacuum_scale_factor: 0.05
            autovacuum_analyze_threshold: 50
            autovacuum_analyze_scale_factor: 0.02
            autovacuum_freeze_max_age: 50000000
            autovacuum_vacuum_cost_limit: 1000
            autovacuum_vacuum_cost_delay: 1	
            
            # Logging configs
            log_destination: 'csvlog'
            logging_collector: on
            log_rotation_age: 1d
            log_rotation_size: 100MB
            log_truncate_on_rotation: off
            log_min_messages: warning
            log_min_error_statement: error
            log_min_duration_statement: 1
            log_checkpoints: on
            log_line_prefix: '%m [%p] [%a] [%u] [%d] [%r] [%Q] [%i] [%e] [%c] | '
            #log_statement: 'all'
            log_timezone: 'Asia/Ho_Chi_Minh'
            #log_destination: 'stderr'
            log_directory: 'log'
            log_filename: 'postgresql-%Y-%m-%d_%H%M%S.log'
            #log_line_prefix: '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
            log_connections: 'on'
            log_disconnections: 'on'
            log_lock_waits: 'on'
            log_temp_files: 0
            log_autovacuum_min_duration: 0
            log_statement: 'mod'
      # some desired options for 'initdb'
      initdb: # Note: It needs to be a list (some options need values, others are switches)
          - encoding: UTF8
          - data-checksums
      pg_hba: # Add following lines to pg_hba.conf after running 'initdb'
          - host replication replicator 127.0.0.1/32 trust
          - host replication replicator   10.84.2.40/32   trust
          - host replication replicator   10.84.2.41/32   trust
          - host replication replicator   10.84.2.42/32   trust
          - host all all 0.0.0.0/0 md5
    
      # Some additional users which needs to be created after initializing new cluster 
    postgresql:
        cluster_name: cluster_1
        listen: 0.0.0.0:5432
        connect_address: ${NODE_IP}:5432
        data_dir: /var/lib/pgsql/16/data/
        bin_dir: /usr/pgsql-16/bin
        pgpass: /tmp/pgpass
        authentication:
            replication:
                username: replicator
                password: replPasswd
            superuser:
                username: postgres
                password: qaz123
        parameters:
            unix_socket_directories: "/var/run/postgresql/"
            unix_socket_directories: "/var/run/postgresql/"
            archive_mode: on
            archive_command: 'pgbackrest --stanza=cluster_1 archive-push %p'
            restore_command: "pgbackrest --stanza=cluster_1 archive-get %f %p"
            max_connections: 5000
            shared_buffers: 2GB
            effective_cache_size: 2GB
            maintenance_work_mem: 1GB
            checkpoint_completion_target: 0.9
            wal_buffers: 16MB
            default_statistics_target: 100
            random_page_cost: 1.1
            effective_io_concurrency: 200
            work_mem: 1048kB
            huge_pages: off
            min_wal_size: 2GB
            max_wal_size: 8GB
            max_worker_processes: 16
            max_parallel_workers_per_gather: 4
            max_parallel_workers: 16
            max_parallel_maintenance_workers: 4
            datestyle: 'iso, ymd'
            timezone: 'Asia/Ho_Chi_Minh'
            default_text_search_config: 'pg_catalog.english'
            shared_preload_libraries: 'pgaudit,pg_stat_statements'
            #shared_preload_libraries: 'pgaudit'
            pg_stat_statements.max: 10000
            pg_stat_statements.track: all
            track_activity_query_size: 2048
            autovacuum_max_workers: 5
            autovacuum_naptime: 30
            autovacuum_vacuum_threshold: 50
            autovacuum_vacuum_scale_factor: 0.05
            autovacuum_analyze_threshold: 50
            autovacuum_analyze_scale_factor: 0.02
            autovacuum_freeze_max_age: 50000000
            autovacuum_vacuum_cost_limit: 1000
            autovacuum_vacuum_cost_delay: 1	
            
            # Logging configs
            log_destination: 'csvlog'
            logging_collector: on
            log_rotation_age: 1d
            log_rotation_size: 100MB
            log_truncate_on_rotation: off
            log_min_messages: warning
            log_min_error_statement: error
            log_min_duration_statement: 1
            log_checkpoints: on
            log_line_prefix: '%m [%p] [%a] [%u] [%d] [%r] [%Q] [%i] [%e] [%c] | '
            #log_statement: 'all'
            log_timezone: 'Asia/Ho_Chi_Minh'
            #log_destination: 'stderr'
            log_directory: 'log'
            log_filename: 'postgresql-%Y-%m-%d_%H%M%S.log'
            #log_line_prefix: '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
            log_connections: 'on'
            log_disconnections: 'on'
            log_lock_waits: 'on'
            log_temp_files: 0
            log_autovacuum_min_duration: 0
            log_statement: 'mod'
        create_replica_methods:
            - pgbackrest
            - basebackup
        pgbackrest:
            command: /usr/bin/pgbackrest --stanza=cluster_1 --type=full --log-level-console=info backup
            keep_data: true
            no_params: true
            no_leader: true
    watchdog:
        mode: off 
    tags:
        nofailover: false
        noloadbalance: false
        clonefrom: false
        nosync: false
    logging:
        level: INFO
        format: '%(asctime)s - %(levelname)s - %(message)s'
        loggers:
            root:
                handlers: [file]
                level: INFO
        handlers:
            file:
                class: logging.FileHandler
                level: INFO
                formatter: default
                filename: /var/log/patroni/patroni.log
        formatters:
            default:
                format: '%(asctime)s - %(levelname)s - %(message)s'
    " | sudo tee -a /etc/patroni/patroni.yml

#### Create patroni data directory on node1,node2 and node3:

    mkdir -p  /data/patroni
    chown postgres:postgres /data/patroni/
    chmod 700 /data/patroni/
    mkdir -p /var/log/patroni
    touch /var/log/patroni/patroni.log
    chown postgres:postgres /var/log/patroni/patroni.log
    chmod 640 /var/log/patroni/patroni.log

#### Create systemd file for patroni on node1,node2,node3:

    vi  /etc/systemd/system/patroni.service
    
    
    
    [Unit]
    Description=Runners to orchestrate a high-availability PostgreSQL
    After=syslog.target network.target 
    
    [Service]
    Type=simple 
    
    User=postgres
    Group=postgres 
    
    # Start the patroni process
    ExecStart=/bin/patroni /etc/patroni/patroni.yml 
    
    # Send HUP to reload from patroni.yml
    ExecReload=/bin/kill -s HUP $MAINPID 
    
    # only kill the patroni process, not its children, so it will gracefully stop postgres
    KillMode=process 
    
    # Give a reasonable amount of time for the server to start up/shut down
    TimeoutSec=30 
    
    # Do not restart the service if it crashes, we want to manually inspect database on failure
    Restart=no 

    StandardOutput=file:/var/log/patroni/patroni.log
    StandardError=file:/var/log/patroni/patroni.log
    
    [Install]
    WantedBy=multi-user.target
    
    
    systemctl daemon-reload
    
    systemctl start patroni
    
    
    ln -s /usr/local/bin/patronictl /usr/local/sbin

#### check

    patronictl -c /etc/patroni/patroni.yml  list

#### config HAproxy on all node

    vi /etc/haproxy/haproxy.cfg
    # Add lines to this config
    
    global
          maxconn 100
           log 127.0.0.1:514  local0 info
    defaults
          log global
          mode tcp
          retries 2
          timeout client 30m
          timeout connect 4s
          timeout server 30m
          timeout   check   5s
    listen stats
          mode http
          bind *:7000
          stats enable
          stats uri /
    listen primary
          bind *:5000
          option httpchk /primary
          http-check expect status 200
          default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
          server d-postgres-01 10.84.2.40:5432 maxconn 100   check   port 8008
          server d-postgres-02 10.84.2.41:5432 maxconn 100   check   port 8008
          server d-postgres-03 10.84.2.42:5432 maxconn 100   check   port 8008

    listen standbys
        balance roundrobin
        bind *:5001
        option httpchk /replica 
        http-check expect status 200
        default-server inter 3s fall 3 rise 2 on-marked-down shutdown-sessions
          server d-postgres-01 10.84.2.40:5432 maxconn 100   check   port 8008
          server d-postgres-02 10.84.2.41:5432 maxconn 100   check   port 8008
          server d-postgres-03 10.84.2.42:5432 maxconn 100   check   port 8008


### upgrade postgresql
    patronictl list
#### stop patroni trên các Replica trước
    systemctl stop patroni
#### cài đặt trên tất cả các nodes
    dnf install postgresql17-server postgresql17-contrib postgresql17-devel
    dnf install https://download.postgresql.org/pub/repos/yum/17/redhat/rhel-9-x86_64/system_stats_17-3.2-1PGDG.rhel9.x86_64.rpm
    dnf install https://download.postgresql.org/pub/repos/yum/17/redhat/rhel-9-x86_64/postgresql17-contrib-17.6-1PGDG.rhel9.x86_64.rpm
#### thực hiện trên leader
    pg_dumpall -h <primary_host> -U postgres -f /backup/full_backup.sql
    systemctl stop patroni
#### remove cluster 
    patronictl remove cluster_1
    su - postgres
    /usr/pgsql-17/bin/initdb -D /var/lib/pgsql/17/data --encoding=UTF8 --locale=en_US.UTF-8 --data-checksums
    /usr/pgsql-17/bin/pg_upgrade --old-bindir /usr/pgsql-16/bin/ --new-bindir /usr/pgsql-17/bin  --old-datadir /var/lib/pgsql/16/data/ --new-datadir /var/lib/pgsql/17/data/ --check
    /usr/pgsql-17/bin/pg_upgrade -b /usr/pgsql-16/bin/ -B /usr/pgsql-17/bin -d /var/lib/pgsql/16/data/ -D /var/lib/pgsql/17/data/ -o "-c config_file=/var/lib/pgsql/16/data/postgresql.conf" -O "-c config_file=/var/lib/pgsql/17/data/postgresql.conf"
    cp 16/data/pg_hba.conf 17/data/
    cp 16/data/patroni.dynamic.json 17/data/

#### về lại root sửa patroni.yaml. sửa lại  data_dir và bin_dir về đường dẫn đến postgresql 17
#### sửa 2 tham số  data_dir và bin_dir trên tất cả các node postgresql
    su - postgres
#### test trước khi start patroni
    /bin/patroni /etc/patroni/patroni.yml
#### nếu ko phát sinh lỗi gì quay lại root
#### thực hiện lại các bước xóa cluster
    patronictl remove cluster_1
#### start patroni trên leader node trước sau đó đến các Replica (chú ý data_dir và bin_dir )
    systemctl start patroni.service;systemctl status patroni.service
#### kiểm tra lại đường dẫn, version postgres và dữ liệu

### Backup and restore user pgbackrest
- có thể backup ra local hoặc qua NFS
- Hướng dẫn này thực hiện backup qua NFS server

#### triển khai pgbackrest
    dnf install nfs-utils
    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    dnf install epel-release
    dnf install pgbackrest
    pgbackrest --version
    sudo groupadd pgbackrest
    sudo adduser -g pgbackrest -n pgbackrest
    sudo chown -R pgbackrest: /var/log/pgbackrest/
    su - pgbackrest
    ssh-keygen -t rsa -N ""
    touch .ssh/authorized_keys
    chmod 600 .ssh/authorized_keys
#### cài đặt trên postgresql server
- Debian
  
    
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
    apt update
    apt install postgresql-17-pgaudit
    apt install pgbackrest
    pgbackrest version

- Redhat
    

    dnf install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-9-x86_64/pgdg-redhat-repo-latest.noarch.rpm
    dnf install epel-release
    dnf install pgbackrest
    pgbackrest --version

#### cấu hình  pbgbackest server
    vi /etc/pgbackrest.conf

    [global]
    repo1-retention-full=7
    repo1-retention-diff=2
    repo1-retention-archive-type=full
    start-fast=y
    process-max=4
    log-level-console=info
    log-level-file=debug
    archive-timeout=300
    spool-path=/var/spool/pgbackrest
    
    
    [d-pav]
    pg1-path=/postgresql17/main/
    pg1-host=10.84.2.44
    
    repo1-path=/data/pgbackrest/d-pav
    repo1-retention-full=3
    repo1-retention-diff=3

    
#### cấu hình pgbackrest trên postgresql

    vim /etc/pgbackrest.conf
    [global]
    repo1-host=p-backup-db
    repo1-host-user=pgbackrest
    log-level-console=info
    log-level-file=debug
    repo1-retention-full=7
    
    [d-pav]
    pg1-path=/postgresql17/main/

#### trên pgbackrest server

    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info stop
    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info stanza-delete
    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info start
    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info stanza-create
    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info check
    sudo -u pgbackrest pgbackrest --stanza=d-pav --log-level-console=info --type=full backup

### Restore
#### restore toàn bộ db
-    trên postgresql

    sudo -u postgres pgbackrest --stanza=d-pav --log-level-console=info info
    
    sudo -u postgres pgbackrest --stanza=d-pav--delta restore --type=immediate --target-action=pause --set=20251001-092242F
- mở file postgresql.auto.conf thêm vào cuối file recovery_target_action = 'pause'

   
    sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D /postgresql17/main/ start
    
    sudo -u postgres psql -c "SELECT pg_is_in_recovery();"
    watch -n 2 "sudo -u postgres psql -c 'SELECT pg_is_in_recovery(), now(), pg_last_wal_replay_lsn();'"
    sudo -u postgres psql -c "SELECT timeline_id FROM pg_control_checkpoint();"
    sudo -u postgres psql -d db_name -c "\dt"
    sudo -u postgres psql -c "SELECT pg_wal_replay_resume();"
    systemctl start postgresql@17-main.service
#### Specific DB
    
    sudo -u postgres mkdir /postgresql17/restore_temp
    
    sudo -u postgres pgbackrest --stanza=cluster_1 restore --repo1-host=10.84.102.74 --pg1-path=/postgresql17/restore_temp --set=20250929-zzzz --type=immediate --target-action=pause
- mở file postgresql.auto.conf thêm vào cuối file recovery_target_action = 'pause'


    sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D /postgresql17/restore_temp -o "-p 5433 -c listen_addresses=localhost" start
    watch -n 2 "sudo -u postgres psql -p 5433 -c 'SELECT pg_is_in_recovery(), now(), pg_last_wal_replay_lsn();'"
    sudo -u postgres psql -p 5433 -c "SELECT timeline_id FROM pg_control_checkpoint();"
    sudo -u postgres psql -p 5433 -d db_name -c "\dt"
    sudo -u postgres psql -p 5433 -c "SELECT pg_wal_replay_resume();"

    sudo -u postgres /usr/pgsql-17/bin/pg_dump -p 5433 -d db_name -f /tmp/db_name.dump
- cần tạo db_name trước 


    psql -U postgres -d db_name < /tmp/db_name.dump


###### restore PITR
- chú ý: cần check logs để biết chính xác thời gian cần khôi phục


    sudo grep "DELETE" /postgresql17/main/log/postgresql-*.csv
    sudo -u postgres pgbackrest --stanza=d-pav --delta restore  --pg1-path=/var/lib/pgsql/17/restore_temp --db-include=d-pav --type=time --target="2025-10-01 16:07:12" --target-action=pause

- mở file postgresql.auto.conf thêm vào cuối file recovery_target_action = 'pause'


    sudo -u postgres /usr/pgsql-17/bin/pg_ctl -D /var/lib/pgsql/17/restore_temp -o "-p 5433 -c listen_addresses=localhost" start
    watch -n 2 "sudo -u postgres psql -p 5433 -c 'SELECT pg_is_in_recovery(), now(), pg_last_wal_replay_lsn();'"
    sudo -u postgres psql -p 5433 -c "SELECT timeline_id FROM pg_control_checkpoint();"
    sudo -u postgres psql -p 5433 -d db_name -c "\dt"
    sudo -u postgres psql -p 5433 -c "SELECT pg_wal_replay_resume();"

    sudo -u postgres /usr/pgsql-17/bin/pg_dump -p 5433 -d db_name -f /tmp/db_name.dump
- cần tạo db_name trước 


    psql -U postgres -d db_name < /tmp/db_name.dump



        