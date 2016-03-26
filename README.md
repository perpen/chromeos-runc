This is for running a full Linux distrib within Chrome OS.

It uses https://github.com/opencontainers/runc to run a container with a PID namespace, and thus supports systemd.

Just look at these 2 files to understand how the containers are created:
- https://github.com/perpen/chromeos-runc/blob/master/config-template.json
- https://github.com/perpen/chromeos-runc/blob/master/start-container.sh

I have been using this setup with Arch Linux without any issues, only taking from crouton the xiwi stuff. I didn't bother with audio as I just use xiwi for running IntelliJ or Blender but it would be trivial to add.

xiwi: To run xiwi I bind-mounted /proc from the Chrome OS host onto a directory in the container fs. Then I modified `croutonfindnacl` to use this proc directory to lookup the processes in the host.

I am storing this here so it doesn't get lost as I stopped using Chrome OS (for now?). If anybody is interested feel free to ask for more details.
