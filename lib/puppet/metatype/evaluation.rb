class Puppet::Type
    # This method is responsible for collecting property changes we always
    # descend into the children before we evaluate our current properties.
    # This returns any changes resulting from testing, thus 'collect' rather
    # than 'each'.
    def evaluate
        #Puppet.err "Evaluating %s" % self.path.join(":")
        unless defined? @evalcount
            self.err "No evalcount defined on '%s' of type '%s'" %
                [self.title,self.class]
            @evalcount = 0
        end
        @evalcount += 1

        if p = self.provider and p.respond_to?(:prefetch)
            p.prefetch
        end

        # this only operates on properties, not properties + children
        # it's important that we call retrieve() on the type instance,
        # not directly on the property, because it allows the type to override
        # the method, like pfile does
        currentvalues = self.retrieve

        changes = propertychanges(currentvalues).flatten

        # now record how many changes we've resulted in
        if changes.length > 0
            self.debug "%s change(s)" %
                [changes.length]
        end
        self.cache(:checked, Time.now)
        return changes.flatten
    end

    # Flush the provider, if it supports it.  This is called by the
    # transaction.
    def flush
        if self.provider and self.provider.respond_to?(:flush)
            self.provider.flush
        end
    end

    # if all contained objects are in sync, then we're in sync
    # FIXME I don't think this is used on the type instances any more,
    # it's really only used for testing
    def insync?(is)
        insync = true
        
        if property = @parameters[:ensure]
            unless is.include? property
               raise Puppet::DevError,
                        "The is value is not in the is array for '%s'" %
                        [property.name]
            end
            ensureis = is[property]           
            if property.insync?(ensureis) and property.should == :absent
                return true
            end
        end

        properties.each { |property|
            unless is.include? property
               raise Puppet::DevError,
                        "The is value is not in the is array for '%s'" %
                        [property.name]
            end

            propis = is[property]
            unless property.insync?(propis)
                property.debug("Not in sync: %s vs %s" %
                    [propis.inspect, property.should.inspect])
                insync = false
            #else
            #    property.debug("In sync")
            end
        }

        #self.debug("%s sync status is %s" % [self,insync])
        return insync
    end
        
    # retrieve the current value of all contained properties
    def retrieve
         return currentpropvalues
    end
    
    # get a hash of the current properties.  
    def currentpropvalues(override_value = nil)
        # it's important to use the method here, as it follows the order
        # in which they're defined in the object
        return properties().inject({}) { | prophash, property|
                   prophash[property] = override_value.nil? ? 
                                          property.retrieve : 
                                             override_value
                   prophash
               }
    end
     
    # Retrieve the changes associated with all of the properties.
    def propertychanges(currentvalues)
        # If we are changing the existence of the object, then none of
        # the other properties matter.
        changes = []
        ensureparam = @parameters[:ensure]
        if @parameters.include?(:ensure) && !currentvalues.include?(ensureparam)
            raise Puppet::DevError, "Parameter ensure defined but missing from current values"
        end
        if @parameters.include?(:ensure) and ! ensureparam.insync?(currentvalues[ensureparam])
#            self.info "ensuring %s from %s" %
#                [@parameters[:ensure].should, @parameters[:ensure].is]
            changes << Puppet::PropertyChange.new(ensureparam, currentvalues[ensureparam])
        # Else, if the 'ensure' property is correctly absent, then do
        # nothing
        elsif @parameters.include?(:ensure) and currentvalues[ensureparam] == :absent
            #            self.info "Object is correctly absent"
            return []
        else
#            if @parameters.include?(:ensure)
#                self.info "ensure: Is: %s, Should: %s" %
#                    [@parameters[:ensure].is, @parameters[:ensure].should]
#            else
#                self.info "no ensure property"
#            end
            changes = properties().find_all { |property|
                unless currentvalues.include?(property)
                    raise Puppet::DevError, "Property %s does not have a current value", 
                               [property.name]
                end
                ! property.insync?(currentvalues[property])
            }.collect { |property|
                Puppet::PropertyChange.new(property, currentvalues[property])
            }
        end

        if Puppet[:debug] and changes.length > 0
            self.debug("Changing " + changes.collect { |ch|
                    ch.property.name
                }.join(",")
            )
        end

        changes
    end
    
    private 
    # FIXARB: This can go away
    def checknewinsync(currentvalues)
        currentvalues.each { |prop, val|
           if prop.respond_to? :new_insync? and prop.new_insync?(val) != prop.insync?
                           puts "#{prop.name} new_insync? != insync?"
              self.devfail "#{prop.name} new_insync? != insync?"
           end
        }
                
        properties().each { |prop|
            puts "#{prop.name} is missing from current values" if (!currentvalues.include?(prop))
        }
    end
end

# $Id$
