{async, sleep,
collect, where, empty, cat,
clone, deepEqual} = require "fairmont"
{randomKey} = require "key-forge"

# TODO add configuration for cloudfront restrictions.
module.exports = async (config, cf) ->

  {bucketURL, fullyQualify, regularlyQualify, root} = require("../url")(config)
  acm = require("./acm")(
    config,
    (yield require("../../../aws")("us-east-1")).acm
  )

  # Invalidate distribution cache.  Because we are charged per path we specify,
  # it's cheapest to just invalidate everything unless nothing changed.
  invalidate = async (distribution, {dlist, ulist}) ->
    createInvalidation = async ->
      yield cf.createInvalidation
        DistributionId: distribution.Id
        InvalidationBatch:
          CallerReference: "Haiku" + randomKey 32
          Paths:
            Quantity: 1
            Items: ["/*"]

    try
      return null if empty cat dlist, ulist
      {Invalidation} = yield createInvalidation()
    catch e
      console.error "Unexpected response while setting invalidation.", e
      throw new Error()


  set = async (name) ->
    buildSource = (name) ->
      name + ".s3-website-" + config.aws.region + ".amazonaws.com"

    setViewerCertificate = async ->
      if config.aws.cache.ssl
        cert = yield acm.fetch config.aws.hostnames[0]

        ACMCertificateArn: cert
        SSLSupportMethod: 'sni-only'
        MinimumProtocolVersion: 'TLSv1'
        Certificate: cert
        CertificateSource: 'acm'
      else
        CloudFrontDefaultCertificate: true
        MinimumProtocolVersion: 'SSLv3'
        CertificateSource: 'cloudfront'

    buildConfiguration = async (name) ->
      {ssl, priceClass} = config.aws.cache
      protocolPolicy = if ssl then "redirect-to-https" else "allow-all"
      priceClass ||= "100"
      originID = "Haiku9-" + regularlyQualify name

      # Fill out configuration for CloudFront distribution... it's a doozy.
      CallerReference: "Haiku " + randomKey 32
      Comment: "Origin is S3 bucket. Setup by Haiku9."
      Enabled: true
      PriceClass: "PriceClass_" + priceClass
      DefaultRootObject: ""

      Aliases:
        Quantity: 1
        Items: [ name ]

      Origins:
        Quantity: 1
        Items: [
          Id: originID
          DomainName: buildSource name
          CustomOriginConfig:
            HTTPPort: 80
            HTTPSPort: 443
            OriginProtocolPolicy: "http-only"
        ]

      ViewerCertificate: yield setViewerCertificate()

      DefaultCacheBehavior:
        TargetOriginId: originID
        ForwardedValues:
          QueryString: true
          Cookies:
            Forward: "all"
          Headers:
            Quantity: 0
        MinTTL: 0
        MaxTTL: config.aws.cache.expires || 60
        TrustedSigners:
          Enabled: false
          Quantity: 0
        ViewerProtocolPolicy: protocolPolicy
        AllowedMethods:
          Items: [ "GET", "HEAD" ]
          Quantity: 2
          CachedMethods:
            Items: [ "GET", "HEAD" ]
            Quantity: 2
        Compress: false



    createDistribution = async (name) ->
      try
        params = DistributionConfig: yield buildConfiguration name
        distribution = yield cf.createDistribution params
        distribution.isNew = true
        distribution
      catch e
        console.error "Unexpected response while creating CloudFront" +
          "distribution.", e
        throw new Error()

    updateDistribution = async (ETag, Distribution) ->
      try
        params =
          Id: Distribution.Id
          IfMatch: ETag
          DistributionConfig: Distribution.DistributionConfig

        yield cf.updateDistribution params
      catch e
        console.error "Unexpected response while updating CloudFront" +
          "distribution.", e
        throw new Error()


    confirmDistributionConfig = async ({ETag, Distribution}) ->
      distro = clone Distribution.DistributionConfig

      distro.PriceClass = "PriceClass_" + (config.aws.cache.priceClass || "100")
      distro.DefaultCacheBehavior.MaxTTL = config.aws.cache.expires || 60
      distro.ViewerCertificate = yield setViewerCertificate()

      if deepEqual distro, Distribution.DistributionConfig
        Distribution
      else
        updateDistribution ETag, Distribution






    try
      # Search the user's current distributions for ones that matches our needs.
      # If we don't find one, create it. If it's misconfigured, update it.
      list = (yield cf.listDistributions {}).DistributionList.Items

      pattern =
        Aliases:
          Quantity: 1,
          Items: [ regularlyQualify name ]

      matches = collect where pattern, list

      # Create a distribution for this hostname, if it doesn't exist.
      return createDistribution name if empty matches

      # If the distribution does exist, get its ID and current version ETag.
      match = matches[0]
      id = match.Id
      current = yield cf.getDistribution {Id: id}

      # Confirm that the distribution is correctly configured. Return it
      # if true, update it if false and return the new object
      yield confirmDistributionConfig current

    catch e
      console.error "Unexpected response while prepping CloudFront distro", e
      throw new Error()



  sync = async (distribution) ->
    try
      retry = true
      while retry
        data = yield cf.getDistribution Id: distribution.Id
        if data.Distribution.Status == "Deployed"
          retry = false
        else
          yield sleep 15000
    catch e
      console.error "Unexpected response while checking CloudFront " +
        "distribution status."
      throw new Error()


  syncInvalidation = async (distribution, invalidation) ->
    if invalidation && !distribution.isNew
      try
        retry = true
        while retry
          data = yield cf.getInvalidation
            DistributionId: distribution.Id
            Id: invalidation.Id

          if data.Invalidation.Status == "Completed"
            retry = false
          else
            yield sleep 15000
      catch e
        console.error "Unexpected response while checking distribution " +
          "invalidation status.", e
        throw new Error()



  {invalidate, set, sync, syncInvalidation}
