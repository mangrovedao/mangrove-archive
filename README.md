This is the Mangrove monorepo which contains most of the packages developed for the Mangrove.

Some other Mangrove packages (like `mangrove-dApp`) live in their own, separate repos. The rules for which packages go where are not hard and fast; On the contrary, we are experimenting with different structure, in order to figure out what the pros and cons are in our specific circumstances.

# Prerequisites
You must have [Yarn 2](https://yarnpkg.com/) installed, as this monorepo uses [Yarn 2 workspaces](https://yarnpkg.com/features/workspaces) to manage dependencies and run commands on multiple packages.

# Usage
Whenever you clone or pull, you should run Yarn in the root folder afterwards:

```shell
$ yarn
```
This will 

- install/update all dependencies
- set up appropriate symlinks inside the `node_modules` folders of packages that depend on other packages in the monorepo
- install Husky Git hooks.


Then, still in the root folder, to build all packages, run

```shell
$ yarn build
```

Afterwards, if you want to run all tests for all packages, you can run

```shell
$ yarn test
```

To run scripts in individual packages, you can either use [`yarn workspace <workspaceName> <commandName>`](https://yarnpkg.com/cli/workspace/#gatsby-focus-wrapper) command *in any folder*, e.g. to run the tests for the `mangrove.js` package:

```shell
$ yarn workspace @giry/mangrove-js test
```

or you can simply `cd` into the folder and run the command, e.g.:

```shell
$ cd packages/mangrove-js; yarn test
```

Check out the Yarn 2 CLI documentation for more information: https://yarnpkg.com/cli/install .

⚠️ Be aware, that when googling yarn commands, it's often not clear whether the results pertain to Yarn 1 (aka 'Classic') or Yarn 2. Currently (September 2021), most examples and much tool support is implicitly engineered towards Yarn 1.


## Commands on multiple packages at once
You can use [`yarn workspaces foreach <commandName`](https://yarnpkg.com/cli/workspaces/foreach) to run a command on all packages.

If the command should be in topological order you can add the flag `--topological-dev`, e.g.:

```shell
$ yarn workspaces foreach --topological-dev build
```
This will only run `build` in a package after its dependencies in the monorepo have been built.


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
    "build": "yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run build-this-package",
                                                // Build dependencies and this package in topological order
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
    "@giry/mangrove-js": "workspace:*",         // This is an example of a run-time dependency to another package in the monorepo
  },
  "devDependencies": {                          
    "@giry/mangrove-solidity": "workspace:*",   // This is an example of a build-time dependency to another package in the monorepo
                                                
    "eslint": "^7.32.0",                        // You probably want the following development dependencies
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

The Git hook script are in the `.husky/` folder. 
