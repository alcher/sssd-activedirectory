# Main SSSD module
class sssd (
  $domains         = [ 'example.local' ],
  $make_home_dir   = false,
  $filter_users    = [ 'root' ],
  $filter_groups   = [ 'root' ],
  $krb5_realm	   = [ 'EXAMPLE.LOCAL' ],
  $krb5_kpasswd    = [ 'WIN-AD.example.local' ],
  $ad_access_filter 	= [ '(memberOf=cn=LinuxAdmin,ou=sudoers,dc=example,dc=local)' ],
  $user_shell 	   = [ '/bin/bash' ],
  $user_home_directory 	= [ '/home/%u' ],
  $workgroup 	   = [ 'EXAMPLE' ],

  $enumerate = false,
  $ldap_referrals = false,
  $cache_credentials = true,
  $min_id = undef,
  $entry_cache_timeout = 60,
  $krb5_canonicalize = true
) {
  validate_array($domains)
  validate_array($filter_users)
  validate_array($filter_groups)
  validate_bool($make_home_dir)
  validate_bool($enumerate)
  validate_bool($ldap_referrals)
  validate_bool($cache_credentials)
  validate_bool($krb5_canonicalize)
  validate_array($ad_access_filter)
  validate_array($krb5_realm)
  validate_array($krb5_kpasswd)
  validate_array($ad_access_filter)
  validate_array($user_shell)
  validate_array($user_home_directory)
  validate_array($workgroup)

  $pkglist = [ "sssd", "samba-client", "krb5-libs" ]
  package { $pkglist:
    ensure      => installed,
    before      => File['smb_conf', 'sssd_conf', 'krb5_conf'],
  }

  # Require help from AD admin to generate the keytab from AD server which will be use to autheticate the server join domain.
  # command to generate: ktpass --princ <ad admin account>@REALM --mapuser <ad admin account> -pass <password> -out <file name .keytab>

  file { "/etc/default.keytab":
    ensure => "present",
    source => "puppet:///modules/sssd/keytab/default.keytab"
  }

  file { 'smb_conf':
    path        => '/etc/samba/smb.conf',
    mode        => '0600',
    require     => Package['samba-client'],
    content => template('sssd/smb.conf.erb')
  }

  file { 'krb5_conf':
    path        => '/etc/krb5.conf',
    mode        => '0644',
    require     => Package['krb5-libs'],
    content => template('sssd/krb5.conf.erb')
  }
  
  concat { 'sssd_conf':
    path        => '/etc/sssd/sssd.conf',
    mode        => '0600',
    # SSSD fails to start if file mode is anything other than 0600
    require     => Package['sssd'],
  }
  
  concat::fragment{ 'sssd_config':
    target  => 'sssd_conf',
    content => template('sssd/sssd.conf.erb'),
    order   => 10,
  }

 exec { 'adjoin':
     command  => "kinit adjoin@${krb5_realm} -k -t /etc/default.keytab && net ads join createupn=host/`hostname -s`.${domains}@${krb5_realm} -k && net ads keytab create && service sssd stop && rm -f /var/lib/sss/db/* && rm -f /var/lib/sss/mc/* && service sssd start && net ads keytab add host/`hostname -s`.${domains}@${krb5_realm}",
     unless   => "net ads testjoin -k | grep -q 'Join is OK'",
     provider => shell,
     user     => root,
     path     => '/usr/sbin:/usr/bin:/sbin:/bin',
     require  => [
         File['/etc/krb5.conf'],
         File['/etc/default.keytab'],
     ],
     logoutput => true,
     environment => [
         'USER=root',
         'LOGNAME=root',
         'HOME=/root',
     ],
  }

  include sssd::params
  if $min_id == undef {
    $real_min_id = $sssd::params::dist_uid_min
  } else {
    $real_min_id = $min_id
  }

  if $make_home_dir {
    class { 'sssd::homedir': }
  }

  exec { 'authconfig-sssd':
    command     => '/usr/sbin/authconfig --enablesssd --enablesssdauth --enablelocauthorize --update',
    refreshonly => true,
    subscribe   => Concat['sssd_conf'],
  }
  
  service { 'sssd':
    ensure      => running,
    enable      => true,
    subscribe   => Exec['authconfig-sssd'],
  }
}

