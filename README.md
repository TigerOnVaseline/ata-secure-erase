# ata-secure-erase
Secure ATA disk erase, a bash script that runs SECURITY ERASE UNIT on the disk using hdparm

## Usage

./ata-secure-erase.sh [-f] device
./ata-secure-erase.sh -l 

	 -f 	Don't prompt before erasing
	 -l 	List disks
