# Users UID
class sssd::params {
  case $::osfamily {
    'RedHat': {
      $dist_uid_min = 1000
    }
    default: {
      fail('Unsupported distribution')
    }
  }
}
