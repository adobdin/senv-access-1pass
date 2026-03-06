# 1Password CLI Kubernetes & SSH Helper

This setup provides convenient shell functions for selecting Kubernetes configs and SSH keys stored in 1Password using the 1Password CLI (`op`). It allows engineers to quickly switch Kubernetes contexts or load SSH keys directly from 1Password without storing secrets locally.

The workflow uses:
- 1Password Desktop
- 1Password CLI
- fzf for interactive selection
- jq for JSON parsing
- kubectl
- ssh-agent

The kubeconfig or SSH key is fetched on demand from 1Password and stored only temporarily in memory or a short-lived file.

---------------------------------------------------------------------

INSTALLATION

1. Install 1Password Desktop

On macOS:

brew install --cask 1password

Launch the application and sign in to your 1Password account.

Enable CLI integration:

1Password → Settings → Developer → Enable “Integrate with 1Password CLI”

---------------------------------------------------------------------

2. Install 1Password CLI

brew install 1password-cli

Verify installation:

op --version

---------------------------------------------------------------------

3. Sign in to 1Password CLI

If Desktop integration is enabled, run:

op signin

or add the account:

op account add

Verify access:

op vault list

---------------------------------------------------------------------

4. Install required dependencies

brew install jq fzf

Verify:

jq --version
fzf --version

---------------------------------------------------------------------

SETUP

Add the provided shell functions to your shell configuration file.

For example:

~/.zshrc

or create a separate file such as:

~/.zsh/functions/op-tools.zsh

After adding the functions reload your shell:

source ~/.zshrc

---------------------------------------------------------------------

KUBERNETES USAGE

Run:

k-select

An interactive list of Kubernetes configurations stored in 1Password will appear.

Select one and the script will load the kubeconfig into memory and create an alias:

k

Example usage:

k config view
k get pods
k get nodes
k get pods -A

The kubeconfig is never written to disk and is stored only in the environment variable:

KUBE_DATA_CACHE

---------------------------------------------------------------------

LOGOUT

To clear the cached kubeconfig and sign out from the CLI:

k-logout

This command:
- signs out from 1Password CLI
- clears the kubeconfig cache
- removes the kubectl alias

---------------------------------------------------------------------

SSH KEY USAGE

Run:

ssh-select

An interactive list of SSH keys stored in 1Password will appear.

After selecting a key:

- the private key is temporarily written to /tmp
- it is added to ssh-agent
- the key is automatically removed from disk
- the agent keeps the key for 1 hour

Example:

ssh-select
ssh user@server

---------------------------------------------------------------------

1PASSWORD ITEM STRUCTURE

Kubernetes configs must have the tag:

k8s-config

The kubeconfig can be stored in one of the following ways:
- field named "k8s config"
- field named "text"
- attached file

---------------------------------------------------------------------

SSH KEYS

SSH key items must have the tag:

ssh-key

The private key must be stored in a field named either:

private_key

or

private key

---------------------------------------------------------------------

SECURITY NOTES

- kubeconfig is stored only in memory
- SSH keys are written to /tmp temporarily and removed immediately
- ssh-agent lifetime is limited to 1 hour
- secrets are always pulled directly from 1Password

---------------------------------------------------------------------

USEFUL COMMANDS

Check login status:

op whoami

List vaults:

op vault list

List items:

op item list

Sign out:

op signout

---------------------------------------------------------------------

TROUBLESHOOTING

If the CLI is not authenticated:

op signin

If Kubernetes configs do not appear, verify that items contain the tag:

k8s-config

If SSH keys do not appear, verify that items contain the tag:

ssh-key
