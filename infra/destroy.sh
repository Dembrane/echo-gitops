#!/bin/bash

# terraform state list > destroy.txt

TARGETS=""
while read resource; do
  TARGETS="$TARGETS -target=$resource"
done < destroy.txt

terraform destroy $TARGETS