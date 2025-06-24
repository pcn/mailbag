# Changelog

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
