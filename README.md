DSpaceDataPreprocess
====================
(c) 2012 LIBIS/KU Leuven
http://www.libis.be, http://www.kuleuven.be

written by mehmet (dot) celik (at) libis (dot)be


Preprocessing MODS and DIDL records from DSpace inorder to import into PRIMO

#Setup and use
The easiest way to install all libraries is through the bundler tool

`bundle install`

##Update config.yml
set 
* staging_dir: this is the output directory 
* log_dir: all logging will end up here 
* dspace: 
	- host: the url to the OAI provider
	- urn: what you would like the ID prefix to be
* sfx:
	- rsi: url to rsi.cgi to check if record has full text


`--- `
`:staging_dir: ./stage`
`:log_dir: ./log`
`:dspace: `
`  :host: https://lirias.kuleuven.be/oai/request`
`  :urn: "oai:lirias.kuleuven.be:"`
`:sfx: `
`  :rsi: http://librilinks.libis.be/kuleuven/cgi/core/rsi/rsi.cgi`

##dspace_convert_file.rb
Convert a single file.

### USAGE:
`dspace_convert_file.rb IN_FILE`

##dspace_convert_list.rb
Convert a list of files. A file with multiple id's is givin to the script. The file should 
contain 1 record number per line. This script uses OAI to retrieve the record.

###USAGE:
dspace_convert_list.rb file_with_multiple_ids

#License
The complete project is licensed under [GPLv3](http://www.gnu.org/licenses/gpl-3.0.html)