# FeatureFeature

This may someday grow into something similar to what is described at http://compwron.github.io/2015/12/10/features-of-features-with-rails.html

## Requirements

- Enable/disable a feature without deploying
- Granular enable/disable per Tlo (top-level-object, i.e. Merchant, User, Venue…)
- Polymorphic (more than one type of Tlo can have features, i.e. GoatMerchant, CatMerchant)
- Works with ruby on rails (although the principles are extractable)
- Must be pre-enable-able, for usage by non-update-able clients like an android/ios app
- A new feature can be added via the UI (although until there is code to depend on it, it will - do nothing)
- A feature can be edited via the UI (i.e. the minimum_client_version can be increased from - 1.1.1 to 1.1.2 if for example the 1.1.1 client has a bug that makes the feature work unreliably)

## Assumptions

A Tlo can have multiple devices which are under its purview, but they must all be on the same version of the app, i.e. upgrading one android tablet (Bob) to version 1.1.2 of the app will force all other devices (Alice, Charles) which are owned by Bob’s Tlo to refuse to work until they too are using exactly version 1.1.2 of the app.

## Regions of code

- A database migration to hold our tables
- The TLO
- Fancy fire-on-enable hooks
- An admin-only UI, where you can turn on a feature_type for any percentage, number, or list of TLOs

## Rationale

This rationale does not apply to all situations.

The situation that I specifically believe that it applies to, is where you have a large number of distinct customers (merchants, venues, clients, etc) which are each a tiny yet larger-than-individual-transaction percentage of your traffic flow. It is persistent object- usually the “main” object in your data model.

If your server and its features are consumed by an android or ios app, which cannot be released or hotfixed instantly, especially if your product organization or technical strategy disallows you from forcing your users to upgrade (i.e. the normal operation of their business absolutely depends on your app, and they are understandably wary of upgrading)

## References

- http://blog.acolyer.org/2015/10/16/holistic-configuration-management-at-facebook/
- http://confreaks.tv/videos/rubyconf2015-a-tale-of-two-feature-flags
- http://martinfowler.com/bliki/FeatureToggle.html
- https://www.ruby-toolbox.com/search?utf8=%E2%9C%93&q=feature+toggle

## Other gems

- https://github.com/mgsnova/feature
- https://github.com/balvig/chili
- https://github.com/ThoughtWorksStudios/feature_toggle
- https://github.com/caelum/envie
- https://github.com/att14/toggles
- https://github.com/jaymcaliley/togg
- https://github.com/rmg/feature_definitions
- https://github.com/rackerlabs/bit_toggle
- https://github.com/thefury/simple_toggle
- https://github.com/eturino/feature_toggle_service
- https://github.com/codebreakdown/togls
