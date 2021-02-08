#!/usr/bin/env bash
# Fail on any error
set -e

# Set version info
export BOX_VERSION_BASE=0.1.0
export CENTOS_BASE_ISO="CentOS-7-x86_64-Minimal-2009.iso"
export CENTOS_BASE_ISO_SHA256="07b94e6b1a0b0260b94c83d6bb76b26bf7a310dc78d7a9c7432809fb9bc6194a"

# Set versions requested of main components (These will be used in Packer and passed to Ansible downstream)
export ANSIBLE_VERSION=2.10.5
# There is a bug in cryptography requirements version 3.4.0 / 3.4.1 that blocks ansible install. See https://github.com/pypa/setuptools/issues/2353
# And it looks like since version 3.4.0 python 2 support has been dropped, which we still need because of ansible-yum integration.
export CRYPTOGRAPHY_VERSION=3.3.2

# Set versions of supported tools, if they don't match, a warning will be shown on screen
export VIRTUALBOX_VERSION="6.1.16"
export PACKER_VERSION="1.6.5"
export VAGRANT_VERSION="2.2.14"

# Set the Vagrant cloud user and box name (make sure you have admin permissions to, or are the owner of this repository)
export VAGRANT_CLOUD_BOX_USER="ilionx"
export VAGRANT_CLOUD_BOX_NAME="centos7"

# ############################################################################################## #
# Below this point there should be no need to edit anything, unless you know what you are doing! #
# ############################################################################################## #

# Generate the final version of the box, adding the date string of today
export BOX_VERSION=${BOX_VERSION_BASE}-$(date +'%Y%m%d')

echo "Testing if all required tools are installed, please wait..."

# Check if all required tools are installed
if ( ! ( vboxmanage --version >/dev/null 2>&1 && packer version >/dev/null 2>&1 && vagrant version >/dev/null 2>&1 ) )
then
    echo "ERROR: One of the required tools (VirtualBox, Vagrant, and Packer) is not installed. Cannot continue."
    exit 1
fi

# Check the tool versions
INSTALLED_VIRTUALBOX_VERSION=$(vboxmanage --version)
INSTALLED_PACKER_VERSION=$(packer --version)
INSTALLED_VAGRANT_VERSION=$(vagrant --version | awk '{print $2}')

if [[ $INSTALLED_VIRTUALBOX_VERSION != $VIRTUALBOX_VERSION || $INSTALLED_PACKER_VERSION != $PACKER_VERSION || $INSTALLED_VAGRANT_VERSION != $VAGRANT_VERSION ]]
then
    echo "WARNING: One of the tool versions does not match the tested versions. Your mileage may vary..."
    echo " * Using VirtualBox version ${INSTALLED_VIRTUALBOX_VERSION} (tested with version ${VIRTUALBOX_VERSION})"
    echo " * Using Packer version ${INSTALLED_PACKER_VERSION} (tested with version ${PACKER_VERSION})"
    echo " * Using Vagrant version ${INSTALLED_VAGRANT_VERSION} (tested with version ${VAGRANT_VERSION})"
    echo ""
    echo -n "To break, press Ctrl-C now, otherwise press Enter to continue"
    read foo
fi

echo "All required tools found. Continuing."

# Check if a build.env file is present, and if so: source it
if [ -f build.env ]
then
    source build.env
fi

# Check if the variables VAGRANT_CLOUD_USER and VAGRANT_CLOUD_TOKEN have been set, if not ask for them
if [ -z "$DEFAULT_VAGRANT_CLOUD_USER" -o -z "$DEFAULT_VAGRANT_CLOUD_TOKEN" ]
then
    # Ask user for vagrant cloud token
    echo -n "What is your Vagrant Cloud username? [ilionx] "
    read user
    user=${user:-ilionx}
    export VAGRANT_CLOUD_USER=${user}

    # Ask user for vagrant cloud token
    echo -n "What is your Vagrant Cloud token? "
    read -s token
    echo ""
    export VAGRANT_CLOUD_TOKEN=${token}
else
    export VAGRANT_CLOUD_USER=$DEFAULT_VAGRANT_CLOUD_USER
    export VAGRANT_CLOUD_TOKEN=$DEFAULT_VAGRANT_CLOUD_TOKEN

    echo "Your vagrant cloud user and token have been sourced from file build.env"
fi

# Export dynamic versioning info
commit=$(git --no-pager log -n 1 --format="%H")
export BOX_VERSION_DESCRIPTION="
## Description
This base box is based on a clean CentOS 7 minimal install. I try to keep the builds up to date with the latest version of this box.

The box defaults to 1 CPU and 1GB of RAM, it is not advised to limit this.

---

## Versions included in this release
Based on box [${BOX_BASE}](https://app.vagrantup.com/centos/boxes/7) version ${BOX_BASE_VERSION}
* Latest OS updates installed at build time
* ansible ${ANSIBLE_VERSION}
* cryptography ${CRYPTOGRAPHY_VERSION}

---

$(cat CHANGELOG.md)

---

## Source info
[View source on Github](https://github.com/Q24/vagrant-box-centos7)

Built on commit: \`${commit}\`
"

echo "${BOX_VERSION_DESCRIPTION}"

# Validate build config
echo "Validating build json files"
packer validate packer.json

# Run the actual build
echo "Building box version ${BOX_VERSION}"
packer build -force -on-error=cleanup packer.json

# Tag git commit for this build
git tag -a "${BOX_VERSION}" -m "Version ${BOX_VERSION} built."