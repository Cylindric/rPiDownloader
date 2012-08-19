rPiDownloader
=============

A script to automate the creation of a headless SABnzbd/SickBeard/CouchPotato server

THIS WILL CURRENTLY PROBABLY NOT WORK, AND MAY TRASH YOUR PI. It's a work in progress...

Usage
-----

Simply log onto your Raspberry Pi, either locally or using SSH, then follow these steps...


1. Install git

    > sudo apt-get update

    > sudo apt-get -y install git

2. Clone this repository

    > git clone git://github.com/Cylindric/rPiDownloader.git

3. Copy the sample configuration file and edit it: (press [Ctrl]+[X], [Y], [Enter] to quit and save)

    > cd rPiDownloader

    > cp install.conf.sample install.conf

    > nano install.conf

4. Run the installer

    > sudo sh ./install.sh
