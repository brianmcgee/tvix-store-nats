{lib, ...}: {
  perSystem = {pkgs, ...}: let
    config = pkgs.writeTextFile {
      name = "nats.conf";
      text = ''
        ## Default NATS server configuration (see: https://docs.nats.io/running-a-nats-service/configuration)

        ## Host for client connections.
        host: "127.0.0.1"

        ## Port for client connections.
        port: 4222

        ## Port for monitoring
        http_port: 8222

        ## Configuration map for JetStream.
        ## see: https://docs.nats.io/running-a-nats-service/configuration#jetstream
        jetstream {}

        # include paths must be relative so for simplicity we just read in the auth.conf file
        include './auth.conf'
      '';
    };
  in {
    config.process-compose = {
      dev.settings.processes = {
        nats-server = {
          working_dir = "$NATS_HOME";
          command = ''${lib.getExe pkgs.nats-server} -c ./nats.conf -DV -sd ./'';
          readiness_probe = {
            http_get = {
              host = "127.0.0.1";
              port = 8222;
              path = "/healthz";
            };
            initial_delay_seconds = 2;
          };
        };
      };
    };

    config.devshells.default = {
      devshell.startup = {
        setup-nats.text = ''
          set -euo pipefail

          # we only setup the data dir if it doesn't exist
          # to refresh simply delete the directory and run `direnv reload`
          [ -d $NSC_HOME ] && exit 0

          mkdir -p $NSC_HOME

          # initialise nsc state

          nsc init -n Tvix --dir $NSC_HOME
          nsc edit operator \
              --service-url nats://localhost:4222 \
              --account-jwt-server-url nats://localhost:4222

          # setup server config

          mkdir -p $NATS_HOME
          cp ${config} "$NATS_HOME/nats.conf"
          nsc generate config --nats-resolver --config-file "$NATS_HOME/auth.conf"

          nsc add account -n Store
          nsc edit account -n Store \
              --js-mem-storage -1 \
              --js-disk-storage -1 \
              --js-streams -1 \
              --js-consumer -1

          nsc add user -a Store -n Admin
          nsc add user -a Store -n Server
        '';
      };
    };

    config.devshells.default = {
      env = [
        {
          name = "NATS_HOME";
          eval = "$PRJ_DATA_DIR/nats";
        }
        {
          name = "NSC_HOME";
          eval = "$PRJ_DATA_DIR/nsc";
        }
        {
          name = "NKEYS_PATH";
          eval = "$NSC_HOME";
        }
        {
          name = "NATS_JWT_DIR";
          eval = "$PRJ_DATA_DIR/nats/jwt";
        }
      ];

      packages = [
        pkgs.nkeys
        pkgs.nats-top
      ];

      commands = let
        category = "nats";
      in [
        {
          inherit category;
          name = "nsc";
          command = ''XDG_CONFIG_HOME=$PRJ_DATA_DIR ${pkgs.nsc}/bin/nsc -H "$NSC_HOME" "$@"'';
        }
        {
          inherit category;
          name = "nats";
          command = ''XDG_CONFIG_HOME=$PRJ_DATA_DIR ${pkgs.natscli}/bin/nats "$@"'';
        }
      ];
    };
  };
}
