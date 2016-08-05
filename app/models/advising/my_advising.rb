module Advising
  class MyAdvising < UserSpecificModel

    include Cache::CachedFeed
    include Cache::FeedExceptionsHandled
    include Cache::JsonifiedFeed
    include Cache::UserCacheExpiry
    include DatedFeed

    def get_feed_internal
      advising_feed = {
        feed: {},
        statusCode: 200
      }

      if Settings.features.advising
        merge_action_items advising_feed
        merge_advisors advising_feed
        merge_appointments advising_feed
        merge_links advising_feed
      end

      advising_feed
    end

    private

    def merge_action_items(advising_feed)
      merge_proxy_feed(advising_feed, CampusSolutions::AdvisorStudentActionItems) do |proxy_feed|
        if (action_items = proxy_feed.fetch(:ucAaActionItems, {}).fetch(:actionItems, nil))
          advising_feed[:feed][:actionItems] = []
          action_items.each do |item|
            next unless item[:actionItemStatus] == 'Incomplete'
            transform_date(item, :actionItemAssignedDate)
            transform_date(item, :actionItemDueDate)
            advising_feed[:feed][:actionItems] << item
          end
        end
      end
    end

    def merge_advisors(advising_feed)
      merge_proxy_feed(advising_feed, CampusSolutions::AdvisorStudentRelationship) do |proxy_feed|
        advising_feed[:feed][:advisors] = proxy_feed.fetch(:ucAaStudentAdvisor, {}).fetch(:studentAdvisor, nil)
      end
    end

    def merge_appointments(advising_feed)
      merge_proxy_feed(advising_feed, CampusSolutions::AdvisorStudentAppointmentCalendar) do |proxy_feed|
        advising_feed[:feed][:appointments] = proxy_feed.fetch(:ucAaAdvisingAppts, {}).fetch(:advisingAppts, nil)
      end
    end

    def merge_links(advising_feed)
      advising_feed[:feed][:links] = {
        manageAppointments: fetch_link('UC_CX_APPOINTMENT_STD_MY_APPTS'),
        newAppointment: fetch_link('UC_CX_APPOINTMENT_STD_ADD')
      }
    end

    def merge_proxy_feed(advising_feed, proxy_class)
      response = proxy_class.new(user_id: @uid).get
      if !response || !response[:feed] || response[:errored]
        advising_feed[:statusCode] = 500
        advising_feed[:errored] = true
        logger.error "Got errors in merged MyAdvising feed on #{proxy_class} for uid #{@uid} with response #{response}"
      else
        yield response[:feed]
      end
    end

    def fetch_link(link_key)
      if (link_feed = CampusSolutions::Link.new.get_url link_key)
        link_feed.try(:[], :feed).try(:[], :link).try(:[], :url)
      end
    end

    def transform_date(item, key)
      item[key] = format_date Time.zone.parse(item[key]).to_datetime
    end

  end
end
