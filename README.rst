Zenoss Analyzer
===============

An attempt at providing a script to help analyze Zenoss Installations.
The script was written in hopes that it could be used to review both 
Core 3, and Core 4 installations, however initial efforts were primarily
focuses on Core 4. Support for Zenoss 2.x was not included

The analyzer will *not* make any changes to your system. It is not intended
to alter your system to obtain an *optimal* configuration. Instead it is
intended to draw your attention to items in your configuration that might
not be optimal

Usage
+++++
Run the following as the **root** user::

   cd /tmp
   wget https://github.com/dpetzel/zenoss_analyzer/zipball/master -O zenoss_analyzer.zip
   unzip -j zenoss_analyzer.zip -d zenoss_analyzer
   sh analyze.sh

Example Output
++++++++++++++
.. image:: https://github.com/dpetzel/zenoss_analyzer/blob/master/docs/example_output.PNG?raw=true

Future Checks
+++++++++++++
Things I want to add but have not yet. A dropping spot as I see solutions posted in the forums and such:: 

* Check that Memcached CACHESIZE is not the default


