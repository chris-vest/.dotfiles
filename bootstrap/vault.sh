#!/bin/bash

export VAULT_ADDR="https://vault.nutmeg.co.uk"
export VAULT_CAPATH="/home/crystal/vault/ca.pem"
vault login -method=github token="7807b9924a044c37b2357669fd58bad2eab619a3"