# Changelog

## [2.1.1](https://github.com/Anras573/AIchemist/compare/v2.1.0...v2.1.1) (2026-02-12)


### Bug Fixes

* wrap MCP servers in mcpServers object per spec ([#39](https://github.com/Anras573/AIchemist/issues/39)) ([621abe8](https://github.com/Anras573/AIchemist/commit/621abe84723d653d499c3fe0af5fd03af12229f4))

## [2.1.0](https://github.com/Anras573/AIchemist/compare/v2.0.0...v2.1.0) (2026-02-12)


### Features

* **skills:** add AGENT.md support to Obsidian skill ([#37](https://github.com/Anras573/AIchemist/issues/37)) ([17ef759](https://github.com/Anras573/AIchemist/commit/17ef7599d25f32656527d15b0f4dc992a716ae4b))

## [2.0.0](https://github.com/Anras573/AIchemist/compare/v1.1.1...v2.0.0) (2026-02-09)


### ⚠ BREAKING CHANGES

* **jira:** jira-agent is no longer available as a Task agent. Use the Jira skill which loads into the main conversation instead.

### Features

* **skills:** add Obsidian knowledge management integration ([#36](https://github.com/Anras573/AIchemist/issues/36)) ([991124f](https://github.com/Anras573/AIchemist/commit/991124fcae76525f3f18dece330b027b9ac66d7c))
* **skills:** add PostgreSQL query skill with safe defaults ([#34](https://github.com/Anras573/AIchemist/issues/34)) ([72c3ac6](https://github.com/Anras573/AIchemist/commit/72c3ac614de966871b421f833bf32c835cc3630d))
* **skills:** add tool-preferences skill for consistent tool selection ([#30](https://github.com/Anras573/AIchemist/issues/30)) ([f6ecb81](https://github.com/Anras573/AIchemist/commit/f6ecb81d3ffdcc3d94e37f8b060858bb69da3a8f))


### Bug Fixes

* **ci:** use manifest mode for release-please to update plugin.json ([#29](https://github.com/Anras573/AIchemist/issues/29)) ([12285fa](https://github.com/Anras573/AIchemist/commit/12285fa690bc5e382126ab35d257df6fa64f790f))


### Code Refactoring

* **jira:** convert agent to skill with confirmation gates ([#24](https://github.com/Anras573/AIchemist/issues/24)) ([601088c](https://github.com/Anras573/AIchemist/commit/601088c67e60224b5038773945471ea60c6b54f1))

## [1.1.1](https://github.com/Anras573/AIchemist/compare/v1.1.0...v1.1.1) (2026-02-01)


### Bug Fixes

* add author email and correct plugin source path ([#19](https://github.com/Anras573/AIchemist/issues/19)) ([5198853](https://github.com/Anras573/AIchemist/commit/519885355e494baf314a2c9c6b0e82879502f76b))
* correct plugin source path in marketplace.json ([#18](https://github.com/Anras573/AIchemist/issues/18)) ([d3d3dd3](https://github.com/Anras573/AIchemist/commit/d3d3dd37f7fd5082c1ef12050eb2fbf1df633f51))
* fixed plugin location inside marketplace.json ([#21](https://github.com/Anras573/AIchemist/issues/21)) ([f520641](https://github.com/Anras573/AIchemist/commit/f52064185560bc977cb8660642fa1a5f581e5efd))
* simplify marketplace.json by removing unnecessary fields ([#16](https://github.com/Anras573/AIchemist/issues/16)) ([786a366](https://github.com/Anras573/AIchemist/commit/786a3663c9c43a569fc5b6a333e11ad5d3aa32a1))
* use correct flat schema for .mcp.json ([#22](https://github.com/Anras573/AIchemist/issues/22)) ([1ee2c9a](https://github.com/Anras573/AIchemist/commit/1ee2c9ac0b7591a0e373f0bbef6a0cab132af8f5))
* use GitHub source format in marketplace.json ([#20](https://github.com/Anras573/AIchemist/issues/20)) ([0924722](https://github.com/Anras573/AIchemist/commit/0924722fbcfd1f49b28957612c00005fd9bebc93))

## [1.1.0](https://github.com/Anras573/AIchemist/compare/v1.0.0...v1.1.0) (2026-01-30)


### Features

* add marketplace.json for plugin distribution ([#14](https://github.com/Anras573/AIchemist/issues/14)) ([fed4a9f](https://github.com/Anras573/AIchemist/commit/fed4a9f098d9b4e77f21c6af6d926e1bef036b70))

## 1.0.0 (2026-01-30)


### Features

* add release-please workflow for automated releases ([83b17af](https://github.com/Anras573/AIchemist/commit/83b17afc7b4dfc9bb20abbd0fa17c1a3cbdd75fb))
* **agents:** add DDD agent for domain modeling guidance ([#9](https://github.com/Anras573/AIchemist/issues/9)) ([42dd17c](https://github.com/Anras573/AIchemist/commit/42dd17c2a5593d6b5209a2d7fed570ec295cfc65))
* **agents:** add TypeScript/React full-stack agent ([#10](https://github.com/Anras573/AIchemist/issues/10)) ([c352f49](https://github.com/Anras573/AIchemist/commit/c352f498da3c23640e60d69d4509b5f6ead6af81))
* **commands:** add code-review command ([#7](https://github.com/Anras573/AIchemist/issues/7)) ([a216422](https://github.com/Anras573/AIchemist/commit/a216422b67f45e0d0bcc7c743f84a4af9faef115))
* integrate code-review command with code-review agent ([#8](https://github.com/Anras573/AIchemist/issues/8)) ([dca7f10](https://github.com/Anras573/AIchemist/commit/dca7f107ff77c92ad3fbe12ac31051c36545eb12))
* **jira:** add auto-configuration for user details ([#11](https://github.com/Anras573/AIchemist/issues/11)) ([3b1ea00](https://github.com/Anras573/AIchemist/commit/3b1ea009dc5327887f33f3d0b272746883bfc221))


### Bug Fixes

* address plugin validation warnings and add proactive agent examples ([#13](https://github.com/Anras573/AIchemist/issues/13)) ([f05afdf](https://github.com/Anras573/AIchemist/commit/f05afdf4ebb3145b82b037bd033904d5e7f8288b))
