#!/bin/bash -e


terraform -chdir="$(pwd)/kind" destroy -no-color -compact-warnings -auto-approve