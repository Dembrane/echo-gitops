# echo-gitops

![image](https://github.com/user-attachments/assets/9d5f4ab4-4fdd-40ef-83fe-43ce9c9384be)

## Infrastructure ([infra/](infra/))

steps for now (will be gitops through this repo in the future):

1. fill vars in [infra/terraform.tfvars](infra/terraform.tfvars)

```
do_token = ""
spaces_access_key = ""
spaces_secret_key = ""
vercel_api_token = ""
```

- `do_token` - DigitalOcean token [https://cloud.digitalocean.com/account/api/tokens](https://cloud.digitalocean.com/account/api/tokens)
- `spaces_access_key` - Spaces access key [https://cloud.digitalocean.com/spaces/access_keys?i=deb664](https://cloud.digitalocean.com/spaces/access_keys?i=deb664)
- `spaces_secret_key` - Spaces secret key (Same as above)
- `vercel_api_token` - Vercel API token [https://vercel.com/account/settings/tokens](https://vercel.com/account/settings/tokens)

2. set environment variables for tfstate backend

```
export AWS_ACCESS_KEY_ID=""
export AWS_SECRET_ACCESS_KEY=""
```

- same as `secrets_access_key` and `spaces_secret_key`

3. apply the infra

```
terraform init
terraform apply
```

4. get the outputs

```
terraform output -json
```


