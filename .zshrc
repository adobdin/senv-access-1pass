[[ -z "$ORIGINAL_PS1" ]] && ORIGINAL_PS1="$PS1"

(( $+aliases[k] )) && unalias k
(( $+aliases[kctx] )) && unalias kctx
(( $+aliases[kns] )) && unalias kns
(( $+aliases[ctx] )) && unalias ctx

_k_require_selection() {
  if [[ -z "$KUBE_ITEM_ID" || -z "$KUBE_VAULT_NAME" ]]; then
    printf "Error: No kubeconfig selected. Run 'k-select' first.\n" >&2
    return 1
  fi
}

_k_fetch_raw_config() {
  _k_require_selection || return 1

  local raw_data=""
  local file_id=""

  raw_data=$(op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/k8s config" 2>/dev/null)
  [[ -z "$raw_data" ]] && raw_data=$(op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/text" 2>/dev/null)

  if [[ -z "$raw_data" ]]; then
    file_id=$(
      op item get "$KUBE_ITEM_ID" --format json |
      jq -r '.files[0].id // empty'
    )
    [[ -n "$file_id" ]] && raw_data=$(op read "op://$KUBE_VAULT_NAME/$KUBE_ITEM_ID/$file_id" 2>/dev/null)
  fi

  if [[ -z "$raw_data" ]]; then
    printf "Error: Data not found in fields (k8s config, text) or files.\n" >&2
    return 1
  fi

  printf "%s" "$raw_data"
}

_k_with_temp_config() {
  _k_require_selection || return 1

  local tmp rc
  tmp=$(mktemp) || return 1
  chmod 600 "$tmp" 2>/dev/null || true

  _k_fetch_raw_config > "$tmp"
  rc=$?

  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    return $rc
  fi

  KUBECONFIG="$tmp" "$@"
  rc=$?

  rm -f "$tmp"
  return $rc
}

_k_collect_kubectl_args() {
  REPLY_ARGS=()

  if [[ -n "$KUBE_CONTEXT_NAME" ]]; then
    REPLY_ARGS+=(--context "$KUBE_CONTEXT_NAME")
  fi

  if [[ -n "$KUBE_NAMESPACE" ]]; then
    case " $* " in
      *" -n "*|*" --namespace "*|*" -A "*|*" --all-namespaces "*)
        ;;
      *)
        REPLY_ARGS+=(-n "$KUBE_NAMESPACE")
        ;;
    esac
  fi
}

k-select() {
  unsetopt nomatch
  set -o noglob

  local selection item_id

  selection=$(
    op item list --tags k8s-config --format json |
    jq -r '.[] | [.id, .title, .vault.name, (.tags|join(","))] | @tsv' |
    sort -k2 |
    fzf --delimiter=$'\t' --with-nth=2,3,4 --tabstop=30 --reverse --inline-info
  )

  [[ -z "$selection" ]] && {
    set +o noglob
    setopt nomatch
    return 1
  }

  item_id=$(printf "%s\n" "$selection" | cut -f1)

  export KUBE_ITEM_ID="$item_id"
  export KUBE_ITEM_TITLE="$(printf "%s\n" "$selection" | cut -f2)"
  export KUBE_VAULT_NAME="$(printf "%s\n" "$selection" | cut -f3)"

  unset KUBE_CONTEXT_NAME
  unset KUBE_NAMESPACE

  export PS1="$KUBE_ITEM_TITLE - $ORIGINAL_PS1"

  printf "Selected kubeconfig: %s\n" "$KUBE_ITEM_TITLE"

  set +o noglob
  setopt nomatch
}

k() {
  _k_require_selection || return 1

  local -a final_args
  _k_collect_kubectl_args "$@"
  final_args=("${REPLY_ARGS[@]}" "$@")

  _k_with_temp_config command kubectl "${final_args[@]}"
}

ctx() {
  _k_require_selection || return 1

  local current target

  current=$(
    _k_with_temp_config kubectl config current-context 2>/dev/null
  )

  target=$(
    _k_with_temp_config kubectl config get-contexts -o name |
    awk -v cur="$current" '
      BEGIN { if (cur != "") print cur }
      !seen[$0]++
    ' |
    fzf \
      --reverse \
      --header "Select Cluster Context (current: $current)" \
      --height 80%
  )

  if [[ -n "$target" ]]; then
    export KUBE_CONTEXT_NAME="$target"
    printf "Context selected: %s\n" "$target"
  fi
}

kns() {
  _k_require_selection || return 1

  local current_ns target_ns
  current_ns="${KUBE_NAMESPACE:-default}"

  target_ns=$(
    k get ns -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null |
    fzf \
      --reverse \
      --header "Select Namespace (current: $current_ns)" \
      --height 80%
  )

  if [[ -n "$target_ns" ]]; then
    export KUBE_NAMESPACE="$target_ns"
    printf "Namespace selected: %s\n" "$target_ns"
  fi
}

kctx() {
  if [[ $# -eq 0 ]]; then
    ctx
    return $?
  fi

  export KUBE_CONTEXT_NAME="$1"
  printf "Context selected: %s\n" "$KUBE_CONTEXT_NAME"
}

k-logout() {
  unset KUBE_ITEM_ID
  unset KUBE_ITEM_TITLE
  unset KUBE_VAULT_NAME
  unset KUBE_CONTEXT_NAME
  unset KUBE_NAMESPACE

  export PS1="$ORIGINAL_PS1"

  op signout >/dev/null 2>&1
  printf "Logged out and selection cleared.\n"
}
