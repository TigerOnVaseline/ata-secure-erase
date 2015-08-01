# ata-secure-erase

A bash script to securely erase ATA disks, runs the `SECURITY ERASE UNIT` command using hdparm.

The script functions along similar lines to `hderase.py`*

Suited to minimal Linux environments, or for those who object to use of Python on religious grounds.

For sensitive uses, care should be taken to validate the erasure, or first overwrite the drive with a pass of zeroes:

https://www.usenix.org/legacy/event/fast11/tech/full_papers/Wei.pdf

## Usage

	./ata-secure-erase.sh [-f] device
	./ata-secure-erase.sh -l 

	 -f 	Don't prompt before erasing
	 -l 	List disks

* https://github.com/yoshiaki-u/hderase.py
