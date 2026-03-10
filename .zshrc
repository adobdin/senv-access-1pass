[[ -z "$ORIGINAL_PS1" ]] && ORIGINAL_PS1="$PS1"

(( $+aliases[k] )) && unalias k
(( $+aliases[kctx] )) && unalias kctx
(( $+aliases[kns] )) && unalias kns

k() {
  local tmp
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubectl "$@"
  local rc=$?

  rm -f "$tmp"
  return $rc
}

kctx() {
  local tmp
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubectx "$@"
  local rc=$?

  rm -f "$tmp"
  return $rc
}

kns() {
  local tmp
  tmp=$(mktemp)

  printf "%s\n" "$KUBE_DATA_CACHE" > "$tmp"

  KUBECONFIG="$tmp" command kubens "$@"
  local rc=$?

  rm -f "$tmp"
  return $rc
}

k-logout() {
  op signout
  unset KUBE_DATA_CACHE
  echo "Logged out and cache cleared."
}

k-select() {
  unsetopt nomatch
  set -o noglob

  local raw_list=$'ID\tTITLE\tVAULT\tTAGS\n'

  raw_list+=$(
    op item list --tags k8s-config --format json |
    jq -r '.[] | [.id, .title, .vault.name, (.tags|join(","))] | @tsv' |
    sort -k2
  )

  local selection=$(echo "$raw_list" | fzf --tabstop=30 --header-lines=1 --reverse --inline-info)

  [[ -z "$selection" ]] && { set +o noglob; return 1; }

  local fields
  IFS=$'\t' read -rA fields <<< "$selection"

  local item_id="${fields[1]}"
  local item_title="${fields[2]}"
  local vault_name="${fields[3]}"

  printf "Loading config for: %s\n" "$item_title"

  local raw_data

  raw_data=$(op read "op://$vault_name/$item_id/k8s config" 2>/dev/null)

  if [[ -z "$raw_data" ]]; then
    raw_data=$(op read "op://$vault_name/$item_id/text" 2>/dev/null)
  fi

  if [[ -z "$raw_data" ]]; then
    local file_id=$(op item get "$item_id" --format json |
      grep -oE '"files" ?: ?\[\{"id" ?: ?"[^"]+"' |
      cut -d'"' -f8)

    if [[ -n "$file_id" ]]; then
      raw_data=$(op read "op://$vault_name/$item_id/$file_id" 2>/dev/null)
    fi
  fi

  if [[ -z "$raw_data" ]]; then
    printf "Error: Data not found in fields (k8s config, text) or files.\n"
    set +o noglob
    return 1
  fi

  export KUBE_DATA_CACHE="$raw_data"

  export PS1="$item_title - $ORIGINAL_PS1"

  printf "Success! Context set for: %s\n" "$item_title"

  set +o noglob
  setopt nomatch
}

ssh-select() {
  unsetopt nomatch
  set -o noglob

  local raw_list=$'ID\tTITLE\tVAULT\tTAGS\n'

  raw_list+=$(
    op item list --tags ssh-key --format json |
    jq -r '.[] | "\(.id)\t\(.title)\t\(.vault.name)\t\(.tags | join(","))"' |
    sort -k2 -t$'\t'
  )

  local selection=$(echo "$raw_list" | fzf --reverse --inline-info --tabstop=30 --header-lines=1)

  [[ -z "$selection" ]] && { set +o noglob; return 1; }

  local item_id=$(echo "$selection" | awk '{print $1}')
  local item_title=$(op item get "$item_id" --format json | jq -r '.title')

  local clean_title=$(echo "$item_title" | tr ' /' '__' | tr -cd '[:alnum:]_')

  echo "Adding key: $item_title"

  local tmp_k="/tmp/${clean_title}"

  op item get "$item_id" --reveal --format json |
    jq -r '.fields[] | select(.id=="private_key" or .label=="private key").value' > "$tmp_k"

  if [[ ! -s "$tmp_k" ]]; then
    echo "Error: Key not found"
    rm -f "$tmp_k"
    set +o noglob
    return 1
  fi

  chmod 600 "$tmp_k"

  ssh-add -t 1h "$tmp_k"

  rm -f "$tmp_k"

  set +o noglob
  setopt nomatch
}
