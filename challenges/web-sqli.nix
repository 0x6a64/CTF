# challenges/web-sqli.nix
#
# Challenge: SQL Injection
# Category:  Web
# Difficulty: Beginner–Intermediate
#
# Scenario:
#   A simple Flask web application runs a login form.  The login query is
#   constructed by string-interpolation and is vulnerable to classic
#   SQL injection.  Exploiting it returns the flag stored in the database.
#
# Goal:
#   Bypass authentication via SQL injection to retrieve the flag.
#
# Local test:
#   nix run .#nixosConfigurations.example-web-player1.config.microvm.declaredRunner
#   # From host: curl http://localhost:8080/login -d "user=admin'--&pass=x"
{ config, pkgs, lib, ... }:

let
  # ---------------------------------------------------------------------------
  # Vulnerable Flask application
  # ---------------------------------------------------------------------------
  appSrc = pkgs.writeText "app.py" ''
    import os, sqlite3
    from flask import Flask, request

    app = Flask(__name__)
    DB  = "/run/ctf-web/users.db"

    def get_db():
        con = sqlite3.connect(DB)
        return con

    def init_db(flag):
        os.makedirs(os.path.dirname(DB), exist_ok=True)
        con = get_db()
        cur = con.cursor()
        cur.executescript("""
            CREATE TABLE IF NOT EXISTS users (
                id       INTEGER PRIMARY KEY,
                username TEXT NOT NULL,
                password TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS secrets (
                id    INTEGER PRIMARY KEY,
                value TEXT NOT NULL
            );
        """)
        # Only insert if the table is empty (idempotent on service restart).
        cur.execute("SELECT COUNT(*) FROM users")
        if cur.fetchone()[0] == 0:
            cur.execute("INSERT INTO users VALUES (1, 'admin', 'hunter2')")
            cur.execute("INSERT INTO users VALUES (2, 'guest', 'guest')")
        cur.execute("SELECT COUNT(*) FROM secrets")
        if cur.fetchone()[0] == 0:
            cur.execute("INSERT INTO secrets VALUES (1, ?)", (flag,))
        con.commit()
        con.close()

    FLAG = open("/etc/flag").read().strip()
    init_db(FLAG)

    @app.route("/")
    def index():
        return """
        <html><body>
          <h2>CTF Login</h2>
          <form method="POST" action="/login">
            Username: <input name="user"/><br/>
            Password: <input name="pass" type="password"/><br/>
            <input type="submit" value="Login"/>
          </form>
        </body></html>
        """

    @app.route("/login", methods=["POST"])
    def login():
        user = request.form.get("user", "")
        pw   = request.form.get("pass", "")
        # Intentionally vulnerable: user input injected directly into the query.
        query = f"SELECT * FROM users WHERE username='{user}' AND password='{pw}'"
        try:
            con = get_db()
            cur = con.cursor()
            cur.execute(query)
            row = cur.fetchone()
            con.close()
        except Exception as e:
            return f"<pre>Error: {e}\nQuery: {query}</pre>", 400

        if row:
            # Successful login returns the flag from the secrets table.
            con    = get_db()
            cur    = con.cursor()
            cur.execute("SELECT value FROM secrets LIMIT 1")
            secret = cur.fetchone()[0]
            con.close()
            return f"<h2>Welcome, {row[1]}!</h2><p>Your reward: <b>{secret}</b></p>"
        return "<h2>Invalid credentials.</h2>", 401

    if __name__ == "__main__":
        app.run(host="0.0.0.0", port=8080)
  '';

  pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ]);

in
{
  # ---------------------------------------------------------------------------
  # Challenge metadata
  # ---------------------------------------------------------------------------
  nixctf.challengeName = "web-sqli";

  # ---------------------------------------------------------------------------
  # Vulnerable web service
  # ---------------------------------------------------------------------------
  systemd.services.ctf-web = {
    description   = "NixCTF SQL Injection Challenge";
    wantedBy      = [ "multi-user.target" ];
    after         = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pythonEnv}/bin/python ${appSrc}";
      Restart   = "on-failure";
      # Run as ctf user; the app reads /etc/flag which is readable by root,
      # but we grant access via a group so the service can seed the DB.
      User  = "ctf-web";
      Group = "ctf-web";
      # Allow reading the flag to seed the database.
      SupplementaryGroups = [];
    };
  };

  # Service user (unprivileged).
  users.users.ctf-web = {
    isSystemUser = true;
    group        = "ctf-web";
  };
  users.groups.ctf-web = {};

  # The flag must be readable by the web service to seed the DB.
  # Override the base permission so ctf-web can read it at startup.
  system.activationScripts.flag-permissions = lib.stringAfter [ "etc" ] ''
    if [ -f /etc/flag ]; then
      chown root:ctf-web /etc/flag
      chmod 0440 /etc/flag
    fi
  '';

  # Open port 8080 inside the VM firewall.
  networking.firewall.allowedTCPPorts = [ 8080 ];

  environment.etc."motd".text = ''
    ╔══════════════════════════════════════════════╗
    ║  NixCTF — SQL Injection                      ║
    ║                                              ║
    ║  A login portal runs on port 8080.           ║
    ║  Can you bypass authentication?              ║
    ║                                              ║
    ║  curl http://localhost:8080/                 ║
    ╚══════════════════════════════════════════════╝
  '';
}
