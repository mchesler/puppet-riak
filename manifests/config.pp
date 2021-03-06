# == Class: riak::config

# Doing some fun stuff such as setting up the repositories
# in the case of centos / rhel, this assumes you haven't installed
# the basho-release-*.rpm.
# there is a bug in our debian startup script -- it doesn't have
# a "status" parameter, yet.  Working around that for now.

class riak::config (
  $absent       = false,
  $manage_repos = true,
) {
  $ulimit = $riak::ulimit
  $limits_template = $riak::limits_template

  $package_repo_type = $::operatingsystem ? {
    /(?i:centos|redhat|Amazon)/ => 'yum',
    /(?i:debian|ubuntu)/        => 'apt',
    # https://github.com/kelseyhightower/puppet-homebrew
    /(?i:darwin)/               => 'brew',
    default                     => 'yum',
  }

  $manage_yum_repo = $absent ? {
    true    => 'absent',
    default => '1',
  }

  $manage_apt_repo = $absent ? {
    true    => 'absent',
    default => 'present',
  }

  if $manage_repos == true {
    case $package_repo_type {
      'apt': {
        file { 'apt-basho':
          ensure  => $manage_apt_repo,
          path    => '/etc/apt/sources.list.d/basho.list',
          content => "deb http://apt.basho.com ${$::lsbdistcodename} main\n",
        }
        package { 'curl':
          ensure => installed,
        }
        exec { 'add-basho-key':
          command => '/usr/bin/curl http://apt.basho.com/gpg/basho.apt.key | /usr/bin/apt-key add -',
          unless  => '/usr/bin/apt-key list | /bin/grep -q "Basho Technologies"',
          require => [ Package['curl'] ],
        }
        exec { 'apt-get-update':
            command     => '/usr/bin/apt-get update',
            subscribe   => File['apt-basho'],
            refreshonly => true,
        }
      }
      'yum': {
        yumrepo { 'basho-products':
          descr     => 'basho packages for $releasever-$basearch',
          baseurl   => 'http://yum.basho.com/el/6/products/$basearch',
          gpgcheck  => 1,
          enabled   => $manage_yum_repo,
          gpgkey    => 'http://yum.basho.com/gpg/RPM-GPG-KEY-basho',
        }
      }
      default: {
        fail("Riak supports apt and yum for package_repo_type and you specified ${package_repo_type}")
      }
    }
  }

  # The sysctl module uses augeas to splice stuff into conf files
  sysctl::conf {
    # Minimize swappiness
    "vm.swappiness": value => 0;
    # Increase default send/receive buffers to 8MB
    "net.core.rmem_default": value => 8388608;
    "net.core.wmem_default": value => 8388608;
    # Increase max send/receive buffers to 128MB
    "net.core.rmem_max": value => 134217728;
    "net.core.wmem_max": value => 134217728;
    # Increase TCP send/receive buffers
    "net.ipv4.tcp_mem": value => '134217728 134217728 134217728';
    "net.ipv4.tcp_rmem": value => '4096 277750 134217728';
    "net.ipv4.tcp_wmem": value => '4096 277750 134217728';
    # Increase the length of the processor input queue
    "net.core.netdev_max_backlog": value => 300000;
    # Increase number of incomign connections
    "net.core.somaxconn": value => 40000;
    # Increase the number of outstanding syn requests allowed
    "net.ipv4.tcp_max_syn_backlog": value => 40000;
    # Decrease the time TCP FIN-WAIT-2 sockets are allowed to stick around
    "net.ipv4.tcp_fin_timeout": value => 15;
    # Allow TIME-WAIT sockets to be reused for new connections
    "net.ipv4.tcp_tw_reuse": value => 1;
    # Allow TIME-WAIT sockets to be recycled
    "net.ipv4.tcp_tw_recycle": value => 1;
    # Decrease wait time between subsequent keepalive probes
    "net.ipv4.tcp_keepalive_intvl": value => 1;
    # Decrease number of probes sent and unacknowledged before the client considers the connection broken and notifies the application layer
    "net.ipv4.tcp_keepalive_probes": value => 5;
    # Decrease interval between last data packet sent and first keepalive probe
    "net.ipv4.tcp_keepalive_time": value => 15;
    # Enable Selective Acknowledgements
    "net.ipv4.tcp_sack": value => 1;
    # Enable large TCP window scaling
    "net.ipv4.tcp_window_scaling": value => 1;
    # Dynamically adjust receive buffer size
    "net.ipv4.tcp_moderate_rcvbuf": value => 1;
  }
  
  # Perform some filesystem tuning...
  # Ensure deadline I/O scheduler is in use
  exec { 'deadline_scheduler':
    command => 'echo deadline > /sys/block/sda/queue/scheduler',
    unless  => 'cat /sys/block/sda/queue/scheduler | grep "\[deadline\]"',
  }
  
  # Increase scheduler depth
  exec { 'scheduler_depth':
    command => 'echo 1024 > /sys/block/sda/queue/nr_requests',
    unless  => '[ $(cat /sys/block/sda/queue/nr_requests) == "1024" ]',
  }
}
