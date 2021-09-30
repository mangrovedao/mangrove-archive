[![CI](https://github.com/giry-dev/mangrove/actions/workflows/node.js.yml/badge.svg)](https://github.com/giry-dev/mangrove/actions/workflows/node.js.yml)

This is the Mangrove monorepo which contains most of the packages developed for the Mangrove.

Some other Mangrove packages (like `mangrove-dApp`) live in their own, separate repos. The rules for which packages go where are not hard and fast; On the contrary, we are experimenting with different structures, in order to figure out what the pros and cons are in our specific circumstances.

# Prerequisites
You must have [Yarn 2](https://yarnpkg.com/) installed, as this monorepo uses [Yarn 2 workspaces](https://yarnpkg.com/features/workspaces) to manage dependencies and run commands on multiple packages.


# Usage
The following sections describe the most common use cases in this monorepo. For more details on how to use Yarn and Yarn workspaces, see the [Yarn 2 CLI documentation](https://yarnpkg.com/cli/install).

⚠️ Be aware that when googling Yarn commands, it's often not clear whether the results pertain to Yarn 1 (aka 'Classic') or Yarn 2. Currently (September 2021), most examples and much tool support is implicitly engineered towards Yarn 1.


## Update monorepo after clone, pull etc.
Whenever you clone, pull, or similar, you should run `yarn build` afterwards, either in the root folder or in a package folder:

```shell
# In ./ or in ./packages/<somePackage>
$ yarn build
```

This will 

1. Run `yarn install` which:
    - installs/updates all dependencies in the monorepo
    - set up appropriate symlinks inside the `node_modules` folders of packages that depend on other packages in the monorepo
    - installs Husky Git hooks.
2. Build all relevant packages for the folder you're in
    - If you're in root, all packages are built
    - If you're in a package folder, all dependencies of the package and the package itself are built (in topological order).

You're clone is now updated and ready to run :-)


## Building and testing a single package
Mostly, you'll only be working on a single package and don't want to build and test the whole monorepo. You just want to build enough such that the current package can be build, tested, and run.

To do this, change into the package directory:

```shell
$ cd packages/<somePackage>
```

and then run:

```shell
$ yarn build
```

This will update dependencies (using `yarn install`) and recursively build the package and its dependencies in topological order.

To build the package *without updating or building its dependencies*, run

```shell
$ yarn build-this-package
```

To test the package, run

```shell
$ yarn test
```

This will run just the tests in the current package.

If you wish to also run the tests of its dependencies, run

```shell
$ yarn test-with-dependencies
```


## Building and testing all packages
To build all packages, run the following in the root folder:

```shell
$ yarn build
```

Afterwards, if you want to run all tests for all packages, you can run

```shell
$ yarn test
```


## Running scripts in a named package
Regardless of the folder you're in, you can always run a script in a particular package by using the [`yarn workspace <packageName> <commandName>`](https://yarnpkg.com/cli/workspace/#gatsby-focus-wrapper) command. E.g. to run the tests for the `mangrove.js` package, run the following in *any folder*:

```shell
$ yarn workspace @giry/mangrove-js test
```


## Commands on multiple packages at once
You can use [`yarn workspaces foreach <commandName>`](https://yarnpkg.com/cli/workspaces/foreach) to run a command on all packages.

If the command should be in topological order you can add the flag `--topological-dev`, e.g.:

```shell
$ yarn workspaces foreach --topological-dev build-this-package
```
This will only run `build-this-package` in a package after its dependencies in the monorepo have been built.


# Structure and contents of this monorepo
The repo root contains the following folders and files:

```bash
.
├── .github/         # GitHub related files, in particular CI configurations for GitHub Actions
├── .husky/          # Husky Git hooks, e.g. for auto formatting
├── .yarn/           # Yarn files
├── packages/        # The actual Mangrove packages
├── .gitattributes   # Git attributes for the whole monorepo 
├── .gitignore       # Git ignore for the whole monorepo
├── .yarnrc.yml      # Yarn 2 configuration
├── README.md        # This README file
├── package.json     # Package file with dependencies and scripts for the monorepo
└── yarn.lock        # Yarn lock file ensuring consistent installs across machines
```


# Packages
Packages should be placed in their own folder under `packages/` and should be structured as regular npm packages.

Each package should have its own `package.json` file based on the following template (though comments should be removed):

```jsonc
{
  "name": "@giry/<packageName>",                // All packages should be scope with @giry
  "version": "0.0.1",
  "author": "Mangrove DAO",
  "description": "<description of the package>",
  "license": "<license",                        // License should be chosen appropriately for the specific package
  "scripts": {
    "precommit": "lint-staged",                 // This script is called by the Husky precommit Git hook.
                                                // We typically use this to autoformat all staged files with `lint-staged`:
                                                // lint-staged runs the command specified in the lint-staged section below
                                                // on the files staged for commit.
    "prepack": "build",                         // Yarn 2 recommends using the `prepack` lifecycle script for building
    "lint": "eslint . --ext .js,.jsx,.ts,.tsx", // Linting of the specified file types.
    "build-this-package": "<build command(s)>", // This script is called by the `build` script in root
    "build": "yarn install && yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run build-this-package",
                                                // Update and build dependencies and this package in topological order
    "test-with-dependencies": "yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run test",
                                                // Test this package and its dependencies in topological order
    "test": "<test command(s)",                 // This script is called by the `test` script in root
  },
  "lint-staged": {
    "**/*": "prettier --write --ignore-unknown" // The command that `lint-staged` will run on staged
                                                // files as part of the Husky precommit Git hook.
                                                // `prettier` will autoformat the files which we generally prefer.
  },
  "dependencies": {
    "@giry/mangrove-js": "workspace:*"          // This is an example of a run-time dependency to another package in the monorepo
  },
  "devDependencies": {                          
    "@giry/mangrove-solidity": "workspace:*",   // This is an example of a build-time dependency to another package in the monorepo
                                                
    "eslint": "^7.32.0",                        // You probably want this and the following development dependencies
    "eslint-config-prettier": "^8.3.0",         // (the version patterns will probably soon be outdated...):
    "eslint-plugin-prettier": "^4.0.0",
    "lint-staged": "^11.1.2",
    "prettier": "2.3.2",
    "prettier-eslint": "^13.0.0" 
  }
}
```


## Lifecycle scripts
Yarn 2 deliberately only supports a subset of the lifecycle scripts supported by npm. So when adding/modifying lifecycle scripts, you should consult Yarn 2's documentation on the subject: https://yarnpkg.com/advanced/lifecycle-scripts#gatsby-focus-wrapper .


## Dependencies inside monorepo
When adding dependencies to another package in the monorepo, you can use `workspace:*` as the version range, e.g.:

```json
"@giry/mangrove-js": "workspace:*"
```

Yarn will resolve this dependency amongst the packages in the monorepo and will use a symlink in `node_modules` for the package. You can add dependencies as either run-time dependencies, in `"dependencies"` or as a build-time dependency, in `"devDependencies"`.

When publishing (using e.g. `yarn pack` or `yarn npm publish`) Yarn will replace the version range with the current version of the dependency.

There are more options and details which are documented in the Yarn 2 documentation of workspaces: https://yarnpkg.com/features/workspaces .


# Yarn configuration
Yarn 2 is configured in two places:

- `package.json`: The `workspaces`section tells Yarn which folders should be considered packages/workspaces.
- `.yarnrc.yml`: Configuraiton of Yarn's internal settings, see https://yarnpkg.com/configuration/yarnrc

A few notes on the reasons for our chosen Yarn 2 configuration:


## `nmHoistingLimits: workspaces`
By default, Yarn hoists dependencies to the highest possible level. However, Hardhat only allows local installs and thus does not support hoisting: https://hardhat.org/errors/#HH12 .

In Yarn 1 (and Lerna) one can prevent hoisting of specific packages, but that's not possible with Yarn 2. We have therefore disabled hoisting past workspaces, i.e., dependencies are always installed in the local `node_modules` folder.


## `nodeLinker: node-modules`
Yarn 2 has introduced an alternative to `node_modules` called "Plug'n'Play". While it sounds promising, it's not fully supported by the ecosystem and we have therefore opted to use the old approach using `node_modules`.


# Git hooks and Husky
We use [Husky](https://typicode.github.io/husky/#/) to manage our Git hooks.

The Git hook scripts are in the `.husky/` folder. 
