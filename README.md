# Installer-ansible

Installer-ansible is a set of scripts for installing services, apps and tweaking operating system on Ubuntu 18.04/20.04 LTS servers.

It is developed to help DevOps simplify the servers automated installation.

startup-cwm:
Functions file

installer-ansible-pull-role:
Base function to pull and install any service that exists in the roles.

# How to Use

 - Clone Repository:
```
git clone https://www.github.com/cloudwm/installer-ansible.git
```

- Edit installer-ansible-service (if customization is needed)

Call Function: pullrole

First variable = Git branch

Second variable = Role specific variables

Example:
pullrole stable '"service=php php_version=8.0"'

- Execute:
```
./installer-ansible-{service_name}
```

# License

This application is allowed to be used, modified or forked by any CWM Cloud Platform User, CWM brand and their users. Any use of this application not for CWM Cloud Platform servers for commerical use is forbidden. You may use this freely for personal use.

<br />
Thanks and enjoy,<br />
CWM Team<br />
