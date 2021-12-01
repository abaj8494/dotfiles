
# Setting PATH for Python 3.9
# The original version is saved in .zprofile.pysave
PATH="/Library/Frameworks/Python.framework/Versions/3.9/bin:${PATH}"
export PATH
export PATH="/Applications/Sublime Text.app/Contents/SharedSupport/bin:$PATH"
export PATH="/Applications/Sublime Text.app/Contents/SharedSupport/bin:$PATH"
export PATH="/Users/aayushbajaj/Google Drive/8. - software/83. - youtube-upload-master/bin:$PATH"
export PATH="/usr/local/bin:$PATH"
function bwauth_get_from_Alfred() {
  local temp_bw_session
  temp_bw_session="$(
    /usr/bin/security find-generic-password \
    -a $wf_keychain_account_name \
    -s $wf_bundle_id -w
  )"
  if [ -n "$temp_bw_session" ]; then
    export BW_SESSION=$temp_bw_session
    echo "successfully retreived token from Keychain"
  else
    unset BW_SESSION
    echo "error fetching token from Keychain" 1>&2
  fi
}

function bwauth_save_to_Alfred() {
  local temp_bw_session
  bwauth_login_via_api 2>/dev/null
  temp_bw_session=$(bw unlock --raw)
  if [ -n "$temp_bw_session" ]; then
    /usr/bin/security add-generic-password -a $wf_keychain_account_name -s $wf_bundle_id -w $temp_bw_session -U
    export BW_SESSION=$temp_bw_session
    echo "saved token to Keychain for use by Alfred workflow"
  else
    unset BW_SESSION
    echo "error unlocking Vault, token was not saved" 1>&2
  fi
}

function bwauth_login_via_api() {
  export BW_CLIENTID=your_api_client_id
  export BW_CLIENTSECRET=your_api_client_secret
  bw login --apikey
}

# Created by `pipx` on 2021-10-23 02:37:28
export PATH="$PATH:/Users/aayushbajaj/.local/bin"
