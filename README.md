# PixeLAW App template
This is a heavily WIP attempt to allow creation of PixeLAW apps without managing the main "game" repo.

# Prerequisites
- Dojo installed

# To get started: 
- Clone this repo
- Run `sozo test`

# Deploying to the demo world
## Build contracts
````shell
sozo build
````

## Deploy contracts
````shell
scarb run deploy_demo
````

## Initialize contracts
````shell
scarb run initialize_demo
````

## Upload manifest
````shell
scarb run upload_manifest_demo
````


# Current issues
- `new_game::tests::test_hunter_actions - panicked with [6445855526543742234424738320591137923774065490617582916 ('CLASS_HASH_NOT_DECLARED'), 23583600924385842957889778338389964899652 ('ENTRYPOINT_FAILED'), 23583600924385842957889778338389964899652 ('ENTRYPOINT_FAILED'), ]`