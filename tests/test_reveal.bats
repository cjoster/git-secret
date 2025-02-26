#!/usr/bin/env bats
# shellcheck disable=SC2155

load _test_base

FILE_TO_HIDE="$TEST_DEFAULT_FILENAME"
FILE_CONTENTS="hidden content юникод"

FINGERPRINT=""


function setup {
  FINGERPRINT=$(install_fixture_full_key "$TEST_DEFAULT_USER")

  set_state_initial
  set_state_git
  set_state_secret_init
  set_state_secret_tell "$TEST_DEFAULT_USER"
  set_state_secret_add "$FILE_TO_HIDE" "$FILE_CONTENTS"
  set_state_secret_hide
}


function teardown {
  rm "$FILE_TO_HIDE"

  uninstall_fixture_full_key "$TEST_DEFAULT_USER" "$FINGERPRINT"
  unset_current_state
}


@test "run 'reveal' with password argument" {
  cp "$FILE_TO_HIDE" "${FILE_TO_HIDE}2"
  rm -f "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]

  cmp -s "$FILE_TO_HIDE" "${FILE_TO_HIDE}2"

  rm "${FILE_TO_HIDE}2"
}


@test "run 'reveal' with bad arg" {
  cp "$FILE_TO_HIDE" "${FILE_TO_HIDE}2"
  rm -f "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -Z -d "$TEST_GPG_HOMEDIR" -p "$password"
  [ "$status" -ne 0 ]
}


@test "run 'reveal' on secret version of file" {
  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password" "$FILE_TO_HIDE$SECRETS_EXTENSION"
  [ "$status" -ne 0 ]
}

@test "run 'reveal' on nonexistent file" {
  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password" "DOES-NOT-EXIST"
  [ "$status" -ne 0 ]
}

@test "run 'reveal' with '-f'" {
  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -f -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' binary with 'SECRETS_GPG_ARMOR=1'" {
  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  # Armor should not change anything here:
  SECRETS_GPG_ARMOR=1 run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' armored with 'SECRETS_GPG_ARMOR=1'" {
  # We need to clean existing binary files:
  git secret clean

  # Now, let's hide files once again with `--armor` enabled:
  set_state_secret_hide '1'

  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  # Armor should not change anything here:
  SECRETS_GPG_ARMOR=1 run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' armored with 'SECRETS_GPG_ARMOR=0'" {
  # We need to clean existing binary files:
  git secret clean

  # Now, let's hide files once again with `--armor` enabled:
  set_state_secret_hide '1'

  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  # Armor should not change anything here:
  SECRETS_GPG_ARMOR=0 run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' with '-v'" {
  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  run git secret reveal -v -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' with '-P'" {
  rm "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")

  local secret_file=$(_get_encrypted_filename "$FILE_TO_HIDE")
  chmod o-rwx "$secret_file"

  run git secret reveal -P -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]

  ## permissions should match.
  local secret_perm
  local file_perm
  file_perm=$($SECRETS_OCTAL_PERMS_COMMAND "$FILE_TO_HIDE")
  secret_perm=$($SECRETS_OCTAL_PERMS_COMMAND "$FILE_TO_HIDE$SECRETS_EXTENSION")
  #echo "# secret_perm: $secret_perm, file_perm: $file_perm" >&3
  [ "$secret_perm" = "$file_perm" ]

  [ -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' with wrong password" {
  rm "$FILE_TO_HIDE"

  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "WRONG"
  [ "$status" -eq 2 ]
  [ ! -f "$FILE_TO_HIDE" ]
}


@test "run 'reveal' for attacker" {
  # Preparations
  rm "$FILE_TO_HIDE"

  local attacker_fingerprint=$(install_fixture_full_key "$TEST_ATTACKER_USER")
  local password=$(test_user_password "$TEST_ATTACKER_USER")

  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  # This should fail, nothing should be created:
  [ "$status" -eq 2 ]
  [ ! -f "$FILE_TO_HIDE" ]

  # Cleaning up:
  uninstall_fixture_full_key "$TEST_ATTACKER_USER" "$attacker_fingerprint"
}


@test "run 'reveal' for attacker with -F (force)" {
  # Preparations
  rm "$FILE_TO_HIDE"

  local attacker_fingerprint=$(install_fixture_full_key "$TEST_ATTACKER_USER")
  local password=$(test_user_password "$TEST_ATTACKER_USER")

  run git secret reveal -F -d "$TEST_GPG_HOMEDIR" -p "$password"

  #echo "# status is $status" >&3

  # This should return a status code of 1 also.  Not sure how to test that we don't die early
  [ "$status" -eq 0 ]
  [ ! -f "$FILE_TO_HIDE" ]

  touch "$FILE_TO_HIDE"  #create this file so uninstall below works

  # Cleaning up:
  uninstall_fixture_full_key "$TEST_ATTACKER_USER" "$attacker_fingerprint"
}


@test "run 'reveal' for multiple users (with key deletion)" {
  # Preparations:
  local second_fingerprint=$(install_fixture_full_key "$TEST_SECOND_USER")
  local password=$(test_user_password "$TEST_SECOND_USER")
  set_state_secret_tell "$TEST_SECOND_USER"
  set_state_secret_hide

  # We are removing a secret key of the first user to be sure
  # that it is not used in decryption:
  uninstall_fixture_full_key "$TEST_DEFAULT_USER" "$FINGERPRINT"

  # Testing:
  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]

  # Cleaning up:
  uninstall_fixture_full_key "$TEST_SECOND_USER" "$second_fingerprint"
}


@test "run 'reveal' for multiple users (normally)" {
  # Preparations:
  local second_fingerprint=$(install_fixture_full_key "$TEST_SECOND_USER")
  # bug in gpg v2.0.22, need to use default password
  local password=$(test_user_password "$TEST_DEFAULT_USER")
  set_state_secret_tell "$TEST_SECOND_USER"
  set_state_secret_hide

  # Testing:
  run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password"

  [ "$status" -eq 0 ]
  [ -f "$FILE_TO_HIDE" ]

  # Cleaning up:
  uninstall_fixture_full_key "$TEST_SECOND_USER" "$second_fingerprint"
}


@test "run 'reveal' with SECRETS_PINENTRY=loopback" {
  rm -f "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  SECRETS_PINENTRY=loopback run git secret reveal \
    -d "$TEST_GPG_HOMEDIR" \
    -p "$password"
  [ "$status" -eq 0 ]
}


@test "run 'reveal' with SECRETS_PINENTRY=error" {
  if [[ "$GPG_VER_MIN_21" -ne 1 ]]; then
    skip "this test is skipped on gpg before version 2.1"
  fi

  rm -f "$FILE_TO_HIDE"

  local password=$(test_user_password "$TEST_DEFAULT_USER")
  SECRETS_PINENTRY=error run git secret reveal \
    -d "$TEST_GPG_HOMEDIR" \
    -p "$password"
  [ "$status" -ne 0 ]
}

@test "run 'reveal' with named file from subdir" {
  local password
  password=$(test_user_password "$TEST_DEFAULT_USER")

  mkdir subdir
  echo "content2" > subdir/new_filename.txt

  ( # start subshell for subdir tests
    cd subdir
    run git secret add new_filename.txt
    [ "$status" -eq 0 ]
    run git secret hide
    [ "$status" -eq 0 ]
  
    run git secret reveal -d "$TEST_GPG_HOMEDIR" -p "$password" new_filename.txt
    [ "$status" -eq 0 ]
  ) # end subshell

  # clean up
  rm -rf subdir
}
