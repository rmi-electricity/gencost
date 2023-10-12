GENCOST CLUSTERING AND REGRESSIONS
Andrew Bartnof, 2023 
For RMI

In order to predict what we call the vom, fom, and som of any new data set, we've written this suite of scripts.
For an in-depth discussion of what these scripts do, cf https://rockmtnins.sharepoint.com/:w:/r/sites/UTF/_layouts/15/Doc.aspx?action=edit&sourcedoc=%7B96384017-d470-4f7a-9ca1-49a27957d20a%7D&wdOrigin=TEAMS-ELECTRON.teamsSdk.openFilePreview&wdExp=TEAMS-CONTROL&web=1

Please note that two tables are generally referred to here:
1. DataBySubplant
2. NewData (this is basically a reference to either EternallyPresent or HistoricalData-- you can punch in whichever you want, as long as you are consistent as you run through these five scripts.


INSTRUCTIONS:

0. module_setup.R
	This script simply lists all of the libraries that you'll need. Please make sure you have all of them installed.

1. module_initial_transformations.R	
	Create variables that we'll need as we move forward.
2. module_pca.R
	DataBySubplant has a lot of colinearity in its variables; use PCA to decompose our data into a few useful components.
3. module_clusters.R			
	We've decided how many clusters we'll use per prime_mover type: now, fit clustering models to the data.
4. module_regressions.R
	Find the optimal linear regression model for each cluster.
5. module_final_transformations.R		
	Calculate the vom, fom, and som for each row of our new data set, and export it to disk.
