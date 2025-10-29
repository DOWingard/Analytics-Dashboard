# 2 Container system

The backend runs on one PostgreSQL container and the front end will run on its own [TODO].

# Backend Container   

Safe starts with tini init processes:
* PostgreSQL server
* SSH server 

Initializes with superusers for the co-founders and an existing ssh key for remote tunneling