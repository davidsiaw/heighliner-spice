# The spice server is just the normal heighliner image with an HTTP front door.
# It inherits the docker CLI, the heighliner gem and the 1Password CLI from it,
# so there is exactly one definition of "what heighliner needs to run".
FROM davidsiaw/heighliner:latest

RUN gem install webrick --no-document

COPY server.rb /app/spice/server.rb
COPY server /app/spice/server

# The wire format, shared by both halves.
COPY wire /app/spice/wire

# The client ships inside the server image so `sp up` can publish it into a
# volume for sandboxes. Same image, same version -- the two cannot drift.
COPY client /app/spice/client

# The skill rides along too, so an agent is told what heighliner is and that the
# missing docker socket is deliberate, instead of discovering it the hard way.
COPY skills /app/spice/skills

EXPOSE 7529 7530

# The base image's entrypoint chdirs into CONTEXT_DIR and runs the CLI. Spice
# does its own chdir per request, so drop it.
ENTRYPOINT []
CMD ["ruby", "/app/spice/server.rb"]
