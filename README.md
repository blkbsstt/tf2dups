# Ruby TF2 API Wrapper and Duplicate Resolver

This repo has a Ruby wrapper around the Steam TF2 API, as well as an example app which uses the wrapper for doing some fun things with duplicate items.

You will need a Steam API key. You can grab one from (http://steamcommunity.com/dev/apikey)[http://steamcommunity.com/dev/apikey].
Copy it to a file named 'apikey' in the project directory (or replace the File.read call in tf2api.rb).

Try `ruby duplicates.rb --accounts=[YOURSTEAMID] --scrap` to calculate the optimal combination of scrapping your duplicates.

Or `ruby duplicates.rb --accounts=[YOURSTEAMID] --friends=[FRIENDA,FRIENDB]` to see if some of your friends are missing items you're just going to scrap anyway.

Run `ruby duplicates.rb --accounts=[STEAMID1,STEAMID2] --list` to see the duplicates across multiple backpacks, if you have mules for instance.

You can specify multiple accounts in combination with any of the other flags, and if you give a list of friends, it will reserve the items the given friends are missing before calculating the optimal scrapping plan.

Run `ruby updateSchema.rb` to generate a cached JSON schema file when new items are released.
You can also just delete the schema.obj that is generated and a new one should be fetched as needed.
