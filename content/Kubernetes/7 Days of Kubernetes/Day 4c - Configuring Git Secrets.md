> [!note]
> This post is part of my [[7 Days Of Kubernetes]] where I explore setting up [a cheap MiniPC](https://amzn.to/42tenCq) as a single-node Kubernetes cluster using k3s.

As we move towards getting more of our config into git we want a way to keep our secrets in git as well. To do this we'll be using [TransCrypt](https://github.com/elasticdog/transcrypt) which will encrypt the secrets before each git commit and decrypt them after each git pull. 

> [!info]
> Ideally we'd use a proper secrets solution like AWS Secrets Manager, GCloud Secret Manager, or a self-hosted Hashicorp Vault. However we don't need to add the complexity of those solutions yet because we're the only user on our server. 

# Install Transcrypt

Transcrypt provides [instructions for installation](https://github.com/elasticdog/transcrypt/blob/main/INSTALL.md) which are pretty straightforwad. We'll summarize those briefly here:

## On MacOS

You can use [homebrew](https://brew.sh/) to install transcrypt:

```bash
brew install transcrypt
```

## On Debian

Installation on Debian isn't quite as simple. We'll need to install required passages, git clone the transcrypt repo, then set up a symlink.

### Install Dependencies
```bash
apt install -y column openssl git bash
```

### Clone the repo

```bash
mkdir -p /var/git/transcrypt;

git clone https://github.com/elasticdog/transcrypt.git /var/git/transcrypt
```

### Create the Symlink

```bash
ln -v -s /var/git/transcrypt/transcrypt /usr/local/bin/transcrypt
```

You should now be able to run `transcrypt --version`  

# Initialize Transcrypt

To use transcrypt in a repo you need to initialize it. To do this, `cd` to your git repo then run the `transcrypt` command:

```
❯ transcrypt

Encrypt using which cipher? [aes-256-cbc] Y
Generate a random password? [Y/n] Y

Repository metadata:

  GIT_WORK_TREE:  /private/tmp/example-repo
  GIT_DIR:        /private/tmp/example-repo/.git
  GIT_ATTRIBUTES: /private/tmp/example-repo/.gitattributes

The following configuration will be saved:

  CONTEXT:  default
  CIPHER:   aes-256-cbc
  PASSWORD: jiSbALq5Fre5rPj7FwU9IHBGyOhc3VvbWnMBs6QP

Does this look correct? [Y/n] Y

The repository has been successfully configured by transcrypt.
```

> [!tip]
> Make sure to save the password and cipher to your password manager.

You can use `transcrypt --show` to get the `transcrypt` command to decrypt the repo on another device:

```
❯ transcrypt --display

[...snip...]

Copy and paste the following command to initialize a cloned repository:

  transcrypt -c aes-256-cbc -p 'jiSbALq5Fre5rPj7FwU9IHBGyOhc3VvbWnMBs6QP'
```

# Add Secrets

I wanted to encrypt any file inside any folder called "secrets". To do this, we add the `**/secrets/*` path to `.gitattributes` file:

```
echo '**/secrets/* filter=crypt diff=crypt merge=crypt' > .gitattributes
```

Now, when we place a file in any directory named `secrets`, transcrypt will automatically encrypt the secrets on commit.

# Test It Out

To validate that transcrypt is working, let's start with an innocuous secret:

```bash
mkdir -p ./k3s/secrets/
echo "this is a secret" > ./k3s/secrets/my-secret
```

Then we can confirm that our `.gitattributes` path is working:

```
❯ git ls-crypt
k3s/secrets/my-secret
```

Now add the secret to git:

```bash
git add ./k3s/secrets/my-secret
git commit -m "First secret"
```
We can then use the `git show` command to look at the raw storage of our secret:

```
❯ git show --no-textconv HEAD:./k3s/secrets/my-secret
U2FsdGVkX1+Ubmtgag7Ta5bJcg6R4Mrlr9IES2S7YWEVG7NR2oM+ekABmWb9iUQ4
```

Great! Our secret is now stored in git fully encrypted!


# Decrypt Secrets on our Remote

As described in [[Day 1b - Deploying Manifests to K3s]], we are applying any manifests in the `./k3s/` directory in our git repo into [the "magic" k3s manifests directory](https://docs.k3s.io/installation/packaged-components). 

To support secrets, we need to update our git hook to copy any files in the `./k3s/secrets/` directory without validating that they are valid yaml.

We will also need to use the `transcrypt` command we get from `transcrypt --display` to have the repo in the k3s manifests directory be able to decrypt the secrets.

## Update the post-update script

In the post-update script, look for the `if $on_master` stanza where we do the `git add .`. Update that stanza to copy al secrets files:

```bash
  if $on_master; then
    msg "Copying encrypted files"
    while read f; do
      dest_f="${release_dir}/${f#$branch_dir}"
      cp_to_dir "$f" "$dest_f"
    done < <(find "${k3s_dir}/secrets/" -type d -name .git -prune -o -type f -print | grep -Eie "[.](yml|yaml|json)$")

    cp "$branch_dir/.gitattributes" "${release_dir}/."

    commit_message=$(git log -1 --pretty=%B | grep -v 'Signed-off-by')

    cd "$release_dir"
    git add .
    git commit -a -m "Release ${commit_message}" || true
    git push origin release
  fi
```

Note that we copy over the `.gitattributes` file as well so that transcrypt on the remote will know which files to decrypt.

## Activate Transcrypt

To activate transcrypt, we `cd` to `/var/lib/rancher/k3s/server/manifests/` then run the transcrypt command:

```bash
cd /var/lib/rancher/k3s/server/manifests/

transcrypt -c aes-256-cbc -p 'jiSbALq5Fre5rPj7FwU9IHBGyOhc3VvbWnMBs6QP' # TODO: use your password instead!

```

Now when our post-update hook pulls in the changes transcrypt will auto-decrypt the secrets!

# Putting it all together

Now we have transcrypt set up at our source repo and our destination repo with our post-update hook tying everything together! Let's try it out be creating a secret:

```bash
# Create the secret
cat > ./k3s/secrets/test-secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: test-secret
  namespace: default
stringData:
  hello: world
EOF

# Add it to git:
git add ./k3s/secrets/test-secret.yaml
git commit -m 'test yaml secret' -- ./k3s/secrets/test-secret.yaml

# Push your changes
git push

# Check if the secret shows up:
kubectl get secret -n default test-secret -o yaml
```

If everything goes well you should see your test secret show up shortly!

---

Next up we want a way to build docker images in our k3s cluster. To do this, we'll use argo-workflows to run jobs when we push to git.  Follow along in [[Day 5 - Deploying Argo Workflows]]!