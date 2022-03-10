module Pod

    class Prebuild
        def self.keyword
            :binary
        end
        def self.use_framework
          :use_framework
        end
    end

    class Podfile
      class TargetDefinition
        @@root_pod_building_options = Array.new

        def self.root_pod_building_options
          @@root_pod_building_options
        end

        ## --- option for setting using prebuild framework ---
        def parse_prebuild_framework(name, requirements)
            building_options = @@root_pod_building_options
            should_prebuild = Pod::Podfile::DSL.prebuild_all
            options = requirements.last
            if options.is_a?(Hash) && options[Pod::Prebuild.keyword] != nil
                should_prebuild = options.delete(Pod::Prebuild.keyword)
                requirements.pop if options.empty?
            end

            pod_name = Specification.root_name(name)

            if options.is_a?(Hash) and options[Pod::Prebuild.use_framework] != nil
              use_framework = options.delete(Pod::Prebuild.use_framework)
              building_options.push(pod_name) if use_framework
              requirements.pop if options.empty?
            end
    
            set_prebuild_for_pod(pod_name, should_prebuild)
        end
        
        def set_prebuild_for_pod(pod_name, should_prebuild)
            
            if should_prebuild == true
                @prebuild_framework_pod_names ||= []
                @prebuild_framework_pod_names.push pod_name
            else
                @should_not_prebuild_framework_pod_names ||= []
                @should_not_prebuild_framework_pod_names.push pod_name
            end
        end

        def prebuild_framework_pod_names
            names = @prebuild_framework_pod_names || []
            if parent != nil and parent.kind_of? TargetDefinition
                names += parent.prebuild_framework_pod_names
            end
            names
        end
        def should_not_prebuild_framework_pod_names
            names = @should_not_prebuild_framework_pod_names || []
            if parent != nil and parent.kind_of? TargetDefinition
                names += parent.should_not_prebuild_framework_pod_names
            end
            names
        end

        # ---- patch method ----
        # We want modify `store_pod` method, but it's hard to insert a line in the 
        # implementation. So we patch a method called in `store_pod`.
        old_method = instance_method(:parse_inhibit_warnings)

        define_method(:parse_inhibit_warnings) do |name, requirements|
          parse_prebuild_framework(name, requirements)
          old_method.bind(self).(name, requirements)
        end
        
      end
    end
end


module Pod
    class Installer

        def prebuild_pod_targets
            @prebuild_pod_targets ||= (
            all = []

            aggregate_targets = self.aggregate_targets
            aggregate_targets.each do |aggregate_target|
                target_definition = aggregate_target.target_definition
                targets = aggregate_target.pod_targets || []

                # filter prebuild
                prebuild_names = target_definition.prebuild_framework_pod_names
                if not Podfile::DSL.prebuild_all
                    targets = targets.select { |pod_target| prebuild_names.include?(pod_target.pod_name) } 
                end
                dependency_targets = targets.map {|t| t.recursive_dependent_targets }.flatten.uniq || []
                targets = (targets + dependency_targets).uniq

                # filter should not prebuild
                explict_should_not_names = target_definition.should_not_prebuild_framework_pod_names
                targets = targets.reject { |pod_target| explict_should_not_names.include?(pod_target.pod_name) } 

                all += targets
            end

            all = all.reject {|pod_target| sandbox.local?(pod_target.pod_name) }
            all.uniq
            )
        end

        # the root names who needs prebuild, including dependency pods.
        def prebuild_pod_names 
           @prebuild_pod_names ||= self.prebuild_pod_targets.map(&:pod_name)
        end


        def validate_every_pod_only_have_one_form

            multi_targets_pods = self.pod_targets.group_by do |t|
                t.pod_name
            end.select do |k, v|
                v.map{|t| t.platform.name }.count > 1
            end

            multi_targets_pods = multi_targets_pods.reject do |name, targets|
                contained = targets.map{|t| self.prebuild_pod_targets.include? t }
                contained.uniq.count == 1 # all equal
            end

            return if multi_targets_pods.empty?

            warnings = "One pod can only be prebuilt or not prebuilt. These pod have different forms in multiple targets:\n"
            warnings += multi_targets_pods.map{|name, targets| "         #{name}: #{targets.map{|t|t.platform.name}}"}.join("\n")
            raise Informative, warnings
        end
        

        old_method = instance_method(:analyze)
        define_method(:analyze) do |analyzer = create_analyzer|
          old_method.bind(self).(analyzer)
          root_pod_building_options = Pod::Podfile::TargetDefinition.root_pod_building_options.clone
          Pod::UI::puts(root_pod_building_options)
          pod_targets.each do |target|
            if not root_pod_building_options.include?("#{target}")
            # Override the target's build time for user provided one
              is_version_1_9_x = Pod.const_defined?(:BuildType) # CP v1.9.x
              # Assign BuildType to proper module definition dependent on CP version.
              # BuildType = is_version_1_9_x ? Pod::BuildType : Pod::Target::BuildType
              target.instance_variable_set(:@build_type, Pod::Target::BuildType.static_library)
            end
          end
        end


    end
end



