# Changelog

## [1.1.11](https://github.com/pcn/mailbag/compare/v1.1.10...v1.1.11) (2025-06-25)


### Bug Fixes

* add missing authdaemonrc template to MTA-SSL service ([a1d2843](https://github.com/pcn/mailbag/commit/a1d284392081e11e6137273c5825d97ae92da399))
* Update courier package versions ([997e7cc](https://github.com/pcn/mailbag/commit/997e7cc7431a82a6ef0ab83a4c8c7f50766049fe))

## [1.1.10](https://github.com/pcn/mailbag/compare/v1.1.9...v1.1.10) (2025-06-25)


### Bug Fixes

* resolve SSL service startup issues ([83aa4bb](https://github.com/pcn/mailbag/commit/83aa4bb48c66c54269592412781d4c9b7f6fd3e0))

## [1.1.9](https://github.com/pcn/mailbag/compare/v1.1.8...v1.1.9) (2025-06-25)


### Bug Fixes

* skip makeuserdb when no test users configured ([7cd68ef](https://github.com/pcn/mailbag/commit/7cd68ef3ce4a81c7f4e65e3148e7bc26192f4b1d))
* skip makeuserdb when no test users configured ([ec3ad66](https://github.com/pcn/mailbag/commit/ec3ad66cd56013b87897f3ad5768acb52d2a6827))

## [1.1.8](https://github.com/pcn/mailbag/compare/v1.1.7...v1.1.8) (2025-06-25)


### Bug Fixes

* resolve makesmtpaccess and IMAP userdb directory issues ([fffd7b6](https://github.com/pcn/mailbag/commit/fffd7b668b18ad681e8b9d0ce85b24a660e5e59b))
* resolve makesmtpaccess and IMAP userdb directory issues ([4932e98](https://github.com/pcn/mailbag/commit/4932e98f374de87f28188c5ff11064fadd7dedc8))

## [1.1.7](https://github.com/pcn/mailbag/compare/v1.1.6...v1.1.7) (2025-06-25)


### Bug Fixes

* resolve IMAP userdb and MTA-SSL template issues ([5647963](https://github.com/pcn/mailbag/commit/56479630d7e80812248a81c24f8e8e3a8daa4db5))
* resolve IMAP userdb and MTA-SSL template issues ([7bc74f1](https://github.com/pcn/mailbag/commit/7bc74f16d7ef8a66c04246210dd0ed02ca2377bb))

## [1.1.6](https://github.com/pcn/mailbag/compare/v1.1.5...v1.1.6) (2025-06-25)


### Bug Fixes

* create missing directories and files for MTA and IMAP ([8990247](https://github.com/pcn/mailbag/commit/8990247e7d76c85ae5b4cec011b798981ba46102))
* create missing directories and files for MTA and IMAP ([642ba70](https://github.com/pcn/mailbag/commit/642ba7001d7d9cbc0776ae3ebde32710646b01b6))

## [1.1.5](https://github.com/pcn/mailbag/compare/v1.1.4...v1.1.5) (2025-06-25)


### Bug Fixes

* add imagePullPolicy Always to all mail services ([0b3a5e0](https://github.com/pcn/mailbag/commit/0b3a5e0efdc4e40416160c4c045b925fe2822754))
* add imagePullPolicy Always to all mail services ([0047aa8](https://github.com/pcn/mailbag/commit/0047aa8f5dfd71458486131242c60dcc8da1cd65))

## [1.1.4](https://github.com/pcn/mailbag/compare/v1.1.3...v1.1.4) (2025-06-25)


### Bug Fixes

* remove unnecessary SMTP access files from IMAP service ([01c904b](https://github.com/pcn/mailbag/commit/01c904bdbc3ce350788fab94473accb68fc9c9db))
* remove unnecessary SMTP access files from IMAP service ([1179260](https://github.com/pcn/mailbag/commit/11792606c2a23c229b4907cf92149e3babc5aa58))

## [1.1.3](https://github.com/pcn/mailbag/compare/v1.1.2...v1.1.3) (2025-06-25)


### Bug Fixes

* resolve MTA aliases and IMAP user issues ([7261ae5](https://github.com/pcn/mailbag/commit/7261ae5435eb9311ef54ae2912b90fd41eab7ff0))
* resolve MTA aliases and IMAP user issues ([24d730c](https://github.com/pcn/mailbag/commit/24d730cb5e269c2b348d903a1e80a267f1c19eee))

## [1.1.2](https://github.com/pcn/mailbag/compare/v1.1.1...v1.1.2) (2025-06-24)


### Bug Fixes

* use monitoring loop to keep containers alive ([af0400e](https://github.com/pcn/mailbag/commit/af0400e5406fe9052d95b3a5b64a465ea17bc988))
* use monitoring loop to keep containers alive ([baca9d4](https://github.com/pcn/mailbag/commit/baca9d48cd0533c1b8585fb1ce2174141c353372))

## [1.1.1](https://github.com/pcn/mailbag/compare/v1.1.0...v1.1.1) (2025-06-24)


### Bug Fixes

* run mail services in foreground mode ([7e73c0b](https://github.com/pcn/mailbag/commit/7e73c0bddb540c14c128e71490cc26c1e703298a))
* run mail services in foreground mode ([c12b74d](https://github.com/pcn/mailbag/commit/c12b74d37c9c9ff5f27ba3809170f82678523536))

## [1.1.0](https://github.com/pcn/mailbag/compare/v1.0.11...v1.1.0) (2025-06-24)


### Features

* add Let's Encrypt ClusterIssuer configuration ([eb89d2d](https://github.com/pcn/mailbag/commit/eb89d2d3a38ac3b8fd8fd15085825f5458a5d9ac))
* create certificates for correct DNS names ([1f11f79](https://github.com/pcn/mailbag/commit/1f11f794a5889a1faa5726a4001b9ddb569c5788))


### Bug Fixes

* update all mail services to use cert-manager secrets ([bdeebe2](https://github.com/pcn/mailbag/commit/bdeebe2c60bbeb85e63f822500b1247e18dbc079))

## [1.0.11](https://github.com/pcn/mailbag/compare/v1.0.10...v1.0.11) (2025-06-24)


### Bug Fixes

* add authdaemonrc configuration template ([c0a1cc9](https://github.com/pcn/mailbag/commit/c0a1cc9d43b3ebac6fe997ce796819c6d9191d20))
* use actual certificate files for esmtpd.pem creation ([15e51b8](https://github.com/pcn/mailbag/commit/15e51b80ed6edc78cbcc5ffb89e097cb242bd058))

## [1.0.10](https://github.com/pcn/mailbag/compare/v1.0.9...v1.0.10) (2025-06-24)


### Bug Fixes

* add ACCESSFILE and PIDFILE variables to esmtpd template ([833a6b2](https://github.com/pcn/mailbag/commit/833a6b2b82799c04c9329c9e4594545247c568b4))
* add templated smtpaccess configuration ([eab0ed6](https://github.com/pcn/mailbag/commit/eab0ed6356503150522abe75a0036a014f7b8d91))

## [1.0.9](https://github.com/pcn/mailbag/compare/v1.0.8...v1.0.9) (2025-06-24)


### Bug Fixes

* add missing MSA configuration fields to context.json ([6bfc8e2](https://github.com/pcn/mailbag/commit/6bfc8e2646d3c31d6c442b340abb0cab77c35f42))
* create service-specific esmtpd base templates ([e66f064](https://github.com/pcn/mailbag/commit/e66f064d02a3d2ce7a3ceb7386e8846db52668e4))
* set imagePullPolicy to Always for MSA container ([a6072c1](https://github.com/pcn/mailbag/commit/a6072c1bf63b08ea09aa7e65966dd15d498c4ca5))

## [1.0.8](https://github.com/pcn/mailbag/compare/v1.0.7...v1.0.8) (2025-06-24)


### Bug Fixes

* add templated esmtpd configuration files ([a3e51f0](https://github.com/pcn/mailbag/commit/a3e51f0039ec2ea6c38bcdb9d14a6ebbde92994a))
* add templated esmtpd configuration files ([afed91a](https://github.com/pcn/mailbag/commit/afed91aef203a19d240e7d70df8ee7da1e4bd918))

## [1.0.7](https://github.com/pcn/mailbag/compare/v1.0.6...v1.0.7) (2025-06-23)


### Bug Fixes

* add esmtpaccess file creation to IMAP entrypoint ([f42cf7e](https://github.com/pcn/mailbag/commit/f42cf7ed29ec6f1ab1a9ac4cd0f94be462e6784c))

## [1.0.6](https://github.com/pcn/mailbag/compare/v1.0.5...v1.0.6) (2025-06-23)


### Bug Fixes

* correct template syntax from Go to minijinja ([0085078](https://github.com/pcn/mailbag/commit/008507881cda516e7f16494a03c6cfd255476d6c))
* create empty esmtpaccess file before running makesmtpaccess ([0d9f097](https://github.com/pcn/mailbag/commit/0d9f09757807e08c6d41718c4ca3c4afa1a757c6))

## [1.0.5](https://github.com/pcn/mailbag/compare/v1.0.4...v1.0.5) (2025-06-23)


### Bug Fixes

* 2025 06 23 ai changes ([0eca526](https://github.com/pcn/mailbag/commit/0eca5266d36f160ff4243c8448773060f64a533c))
* correct courier architecture and permissions ([1df0ec9](https://github.com/pcn/mailbag/commit/1df0ec943b0f774dabf8b54ee948dbc1f1fabaca))
* force image pull for courierd deployment ([07283a1](https://github.com/pcn/mailbag/commit/07283a173f1c653a736364e44ede1d6fec7bcebc))
* run courierd in foreground with proper environment ([eb46484](https://github.com/pcn/mailbag/commit/eb46484a9e1212a3c79e27436b5ca5fe6f25104c))
* run courierd with privileged mode ([4f0995a](https://github.com/pcn/mailbag/commit/4f0995aa7b4194a36f3235534549fe79e486fca2))

## [1.0.4](https://github.com/pcn/mailbag/compare/v1.0.3...v1.0.4) (2025-06-23)


### Bug Fixes

* Merge pull request [#18](https://github.com/pcn/mailbag/issues/18) from pcn/2025-06-23-ai-changes ([52a7d30](https://github.com/pcn/mailbag/commit/52a7d3061c6ebec36801ff44ae4d5be8e443c8d5))
* run courierd container as daemon user (UID 1) ([52a7d30](https://github.com/pcn/mailbag/commit/52a7d3061c6ebec36801ff44ae4d5be8e443c8d5))
* run courierd container as daemon user (UID 1) ([d4c9ee1](https://github.com/pcn/mailbag/commit/d4c9ee1a7725acf3da67cf44cbb0e62e9ed094b1))

## [1.0.3](https://github.com/pcn/mailbag/compare/v1.0.2...v1.0.3) (2025-06-23)


### Bug Fixes

* add missing courier-courierd entrypoint script ([9663189](https://github.com/pcn/mailbag/commit/9663189da7abe572ad83821e726cfdff7e367de8))
* Ai changes ([4156823](https://github.com/pcn/mailbag/commit/4156823865370eab9b36bdf0348696b72b40f09e))
* Merge pull request [#16](https://github.com/pcn/mailbag/issues/16) from pcn/ai-changes ([4156823](https://github.com/pcn/mailbag/commit/4156823865370eab9b36bdf0348696b72b40f09e))

## [1.0.2](https://github.com/pcn/mailbag/compare/v1.0.1...v1.0.2) (2025-06-22)


### Bug Fixes

* update the PAT ([#14](https://github.com/pcn/mailbag/issues/14)) ([33c03a0](https://github.com/pcn/mailbag/commit/33c03a043dad54d844b8471bd614b8133e99cff8))

## [1.0.1](https://github.com/pcn/mailbag/compare/v1.0.0...v1.0.1) (2025-06-22)


### Bug Fixes

* Straighten out the build process ([0eed3f4](https://github.com/pcn/mailbag/commit/0eed3f483c4f23234c4e0617f2ff985042d5acad))
* update rust-action ([#7](https://github.com/pcn/mailbag/issues/7)) ([d75479c](https://github.com/pcn/mailbag/commit/d75479c06ecc4d4bba02cd9b74d157033784bc42))
* use the builds from github ([#5](https://github.com/pcn/mailbag/issues/5)) ([df456ec](https://github.com/pcn/mailbag/commit/df456ec6e474726738b44172e208274bb44dfb39))
* Use the builtin github token ([#10](https://github.com/pcn/mailbag/issues/10)) ([2b53c79](https://github.com/pcn/mailbag/commit/2b53c79f7ff259ad9692ebc7432c9000d4cb613b))

## 1.0.0 (2023-02-28)


### Bug Fixes

* update the todo list ([#3](https://github.com/pcn/mailbag/issues/3)) ([fb84395](https://github.com/pcn/mailbag/commit/fb84395a811b1b20e642b1b3ab5bceee0954d776))
