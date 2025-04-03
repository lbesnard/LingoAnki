{
  pkgs ? import <nixpkgs> { },
}:
let
  fhs = pkgs.buildFHSEnv {
    name = "my-fhs-environment";

    targetPkgs = _: [
      pkgs.micromamba
    ];

    profile = ''
      set -e
      eval "$(micromamba shell hook --shell=posix)"
      envName=lingoAnki

      # https://stackoverflow.com/questions/75080993/dbuserrorresponse-while-running-poetry-install
      export PYTHON_KEYRING_BACKEND=keyring.backends.null.Keyring
      export PYTHONBREAKPOINT="ipdb.set_trace"
      export MAMBA_ROOT_PREFIX=${builtins.getEnv "PWD"}/.mamba
      if ! test -d $MAMBA_ROOT_PREFIX/envs/lingoAnki; then
          micromamba env create --yes -q -f environment.yml && micromamba activate $envName && poetry install --with dev
      fi
      micromamba activate $envName
      set +e
    '';
  };
in
fhs.env
