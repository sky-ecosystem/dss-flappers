PATH := ~/.solc-select/artifacts/solc-0.8.16:~/.solc-select/artifacts/solc-0.5.12:~/.solc-select/artifacts/solc-0.5.16:~/.solc-select/artifacts/solc-0.4.18:~/.solc-select/artifacts:$(PATH)
certora-flapper-univ2           :; PATH=${PATH} certoraRun certora/FlapperUniV2.conf$(if $(rule), --rule $(rule),) --disable_auto_cache_key_gen
certora-flapper-univ2-swap-only :; PATH=${PATH} certoraRun certora/FlapperUniV2SwapOnly.conf$(if $(rule), --rule $(rule),) --cache none
