# A cache for the CachedConfluentSchemaRegistry.
# Extends the InMemoryCache to provide a write-thru to disk for persistent cache.
class AvroTurf::DiskCache < AvroTurf::InMemoryCache

  def initialize(disk_path)
    super()

    # load the write-thru cache on startup, if it exists
    @schemas_by_id_path = File.join(disk_path, 'schemas_by_id.json')
    @schemas_by_id = JSON.parse(File.read(@schemas_by_id_path)) if File.exist?(@schemas_by_id_path)

    @ids_by_schema_path = File.join(disk_path, 'ids_by_schema.json')
    @ids_by_schema = JSON.parse(File.read(@ids_by_schema_path)) if File.exist?(@ids_by_schema_path)

    @schemas_by_subject_version_path = File.join(disk_path, 'schemas_by_subject_version.json')
    @schemas_by_subject_version = {}
  end

  # override
  # the write-thru cache (json) does not store keys in numeric format
  # so, convert id to a string for caching purposes
  def lookup_by_id(id)
    super(id.to_s)
  end

  # override to include write-thru cache after storing result from upstream
  def store_by_id(id, schema)
    # must return the value from storing the result (i.e. do not return result from file write)
    value = super(id.to_s, schema)
    File.write(@schemas_by_id_path, JSON.pretty_generate(@schemas_by_id))
    return value
  end

  # override to use a json serializable cache key
  def lookup_by_schema(subject, schema)
    key = "#{subject}#{schema}"
    @ids_by_schema[key]
  end

  # override to use a json serializable cache key and update the file cache
  def store_by_schema(subject, schema, id)
    key = "#{subject}#{schema}"
    @ids_by_schema[key] = id
    File.write(@ids_by_schema_path, JSON.pretty_generate(@ids_by_schema))
    id
  end

  # checks instance var (in-memory cache) for schema
  # checks disk cache if in-memory cache doesn't exists
  # if file exists but no in-memory cache, read from file and sync in-memory cache
  # finally, if file doesn't exist return nil
  def lookup_by_version(subject, version)
    key = "#{subject}#{version}"
    schema = @schemas_by_subject_version[key]

    return schema unless schema.nil?

    hash = JSON.parse(File.read(@schemas_by_subject_version_path)) if File.exist?(@schemas_by_subject_version_path)
    if hash
      @schemas_by_subject_version = hash
      @schemas_by_subject_version[key]
    end
  end

  # check if file exists and parse json into a hash
  # if file exists take json and overwite/insert schema at key
  # if file doesn't exist create new hash
  # write the new/updated hash to file
  # update instance var (in memory-cache) to match
  def store_by_version(subject, version, schema)
    key = "#{subject}#{version}"
    hash = JSON.parse(File.read(@schemas_by_subject_version_path)) if File.exist?(@schemas_by_subject_version_path)
    hash = if hash
             hash[key] = schema
             hash
           else
             {key => schema}
           end

    write_to_disk_cache(@schemas_by_subject_version_path, hash)

    @schemas_by_subject_version = hash
    @schemas_by_subject_version[key]
  end

  private def write_to_disk_cache(path, hash)
    File.write(path, JSON.pretty_generate(hash))
  end
end
